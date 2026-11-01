import Foundation

/// Latest posts from the Substacks you read.
///
/// 1. Publications: your public profile (https://substack.com/api/v1/user/<handle>/public_profile →
///    `subscriptions[].publication`), plus any you add by hand in Settings.
/// 2. Posts: each publication's archive (https://<domain>/api/v1/archive?sort=new&limit=3),
///    falling back to its RSS feed (https://<domain>/feed) if the archive endpoint fails.
///
/// FRAGILITY: low–medium. The profile and archive endpoints are unofficial but long-standing;
/// RSS is the official fallback. Your profile must show your subscriptions publicly for step 1 —
/// otherwise add publications by hand.
enum SubstackSource {
    struct Publication: Hashable {
        let name: String
        let domain: String
        let logo: URL?
    }

    private struct Profile: Decodable { let subscriptions: [Subscription]? }
    private struct Subscription: Decodable { let publication: Pub }
    private struct Pub: Decodable {
        let name: String?
        let subdomain: String?
        let custom_domain: String?
        let logo_url: String?
    }
    private struct ArchivePost: Decodable {
        let id: Int?
        let title: String?
        let subtitle: String?
        let post_date: String?
        let canonical_url: String?
        let cover_image: String?
        let audience: String?
        let type: String?
        let publishedBylines: [Byline]?
    }
    private struct Byline: Decodable { let name: String? }

    static func fetch(username: String, extra: String) async throws -> SourceResult<SubstackPost> {
        let handle = cleanHandle(username)
        let manual = parseExtra(extra)
        guard !handle.isEmpty || !manual.isEmpty else {
            throw FetchError.notConfigured("Add your Substack username in Settings to see the latest posts from what you read.")
        }

        var warnings: [String] = []
        var publications: [Publication] = []
        if !handle.isEmpty {
            do {
                let subs = try await subscriptions(for: handle)
                publications += subs
                if subs.isEmpty {
                    warnings.append("Your Substack profile doesn't show any subscriptions publicly. Turn that on in Substack, or add publications in Settings.")
                }
            } catch FetchError.badStatus(404, _) {
                if manual.isEmpty {
                    throw FetchError.notConfigured("Substack user “\(handle)” wasn't found. Check the username in Settings.")
                }
                warnings.append("Substack user “\(handle)” wasn't found.")
            } catch {
                if manual.isEmpty { throw error }
                warnings.append("Couldn't load your Substack subscriptions: \(describe(error))")
            }
        }

        // Manual entries first so they always make the cut; de-duplicate by domain.
        var seenDomains = Set<String>()
        let all = (manual + publications).filter { seenDomains.insert($0.domain.lowercased()).inserted }
        guard !all.isEmpty else { return SourceResult(items: [], warnings: warnings) }

        let capped = Array(all.prefix(250))
        if all.count > capped.count {
            warnings.append("Showing the first \(capped.count) of \(all.count) publications.")
        }

        let lists = await boundedMap(capped, limit: 6) { pub -> [SubstackPost]? in
            if let posts = try? await archive(pub), !posts.isEmpty { return posts }
            return try? await rss(pub)
        }
        let failed = lists.filter { $0 == nil }.count
        if failed == capped.count {
            throw FetchError.parse("Substack didn't return any posts — it may be rate-limiting. Try again in a few minutes.")
        }
        if failed > 0 { warnings.append("Couldn't load \(failed) of \(capped.count) publications.") }

        let cutoff = Date().addingTimeInterval(-45 * 86_400)
        var seen = Set<String>()
        let posts = lists.compactMap { $0 }.flatMap { $0 }
            .filter { $0.date >= cutoff && seen.insert($0.id).inserted }
            .sorted { $0.date > $1.date }
        return SourceResult(items: Array(posts.prefix(300)), warnings: warnings)
    }

    // MARK: - Publications

    private static func subscriptions(for handle: String) async throws -> [Publication] {
        guard let url = URL(string: "https://substack.com/api/v1/user/\(handle)/public_profile") else { return [] }
        let profile = try JSONDecoder().decode(Profile.self, from: try await HTTP.data(from: url, accept: "application/json"))
        return (profile.subscriptions ?? []).compactMap { sub in
            let p = sub.publication
            let domain = (p.custom_domain?.isEmpty == false ? p.custom_domain : nil)
                ?? p.subdomain.map { "\($0).substack.com" }
            guard let domain else { return nil }
            return Publication(name: p.name?.trimmingCharacters(in: .whitespaces) ?? domain,
                               domain: domain, logo: p.logo_url.flatMap { URL(string: $0) })
        }
    }

    /// "@sam", "substack.com/@sam", "https://substack.com/@sam" → "sam"
    static func cleanHandle(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = s.range(of: "@", options: .backwards) { s = String(s[r.upperBound...]) }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
    }

    /// One per line (or comma-separated): "willstorr", "willstorr.substack.com", "https://www.thebulwark.com"
    static func parseExtra(_ text: String) -> [Publication] {
        text.split(whereSeparator: { $0 == "\n" || $0 == "," }).compactMap { raw in
            var s = raw.trimmingCharacters(in: .whitespaces)
            guard !s.isEmpty else { return nil }
            if !s.contains("://") { s = "https://" + s }
            guard var host = URL(string: s)?.host?.lowercased() else { return nil }
            if !host.contains(".") { host += ".substack.com" }
            return Publication(name: host.replacingOccurrences(of: ".substack.com", with: "").replacingOccurrences(of: "www.", with: ""),
                               domain: host, logo: nil)
        }
    }

    // MARK: - Posts

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso = ISO8601DateFormatter()

    private static func archive(_ pub: Publication) async throws -> [SubstackPost] {
        guard let url = URL(string: "https://\(pub.domain)/api/v1/archive?sort=new&limit=3") else { return [] }
        let posts = try JSONDecoder().decode([ArchivePost].self, from: try await HTTP.data(from: url, accept: "application/json"))
        return posts.compactMap { p in
            guard let title = p.title, !title.isEmpty,
                  let link = p.canonical_url.flatMap({ URL(string: $0) }),
                  let stamp = p.post_date,
                  let date = isoFractional.date(from: stamp) ?? iso.date(from: stamp) else { return nil }
            return SubstackPost(
                id: link.absoluteString,
                title: title,
                subtitle: p.subtitle?.isEmpty == false ? p.subtitle : nil,
                publication: pub.name,
                author: p.publishedBylines?.first?.name,
                date: date,
                url: link,
                imageURL: p.cover_image.flatMap { URL(string: $0) } ?? pub.logo,
                logoURL: pub.logo,
                isPaid: (p.audience ?? "everyone") != "everyone",
                kind: p.type)
        }
    }

    private static func rss(_ pub: Publication) async throws -> [SubstackPost] {
        guard let url = URL(string: "https://\(pub.domain)/feed") else { return [] }
        let data = try await HTTP.data(from: url, accept: "application/rss+xml,application/xml,*/*;q=0.5")
        let feed = RSSParser.parse(data)
        let name = (pub.logo == nil && !feed.title.isEmpty) ? feed.title : pub.name
        return feed.items.prefix(3).compactMap { item in
            guard let link = URL(string: item.link), let date = item.date else { return nil }
            return SubstackPost(id: link.absoluteString, title: item.title,
                                subtitle: item.summary.isEmpty ? nil : item.summary,
                                publication: name, author: item.author.isEmpty ? nil : item.author,
                                date: date, url: link,
                                imageURL: item.image.flatMap { URL(string: $0) } ?? pub.logo,
                                logoURL: pub.logo, isPaid: false, kind: nil)
        }
    }
}

/// Tiny RSS 2.0 reader — just what the Substack fallback needs.
final class RSSParser: NSObject, XMLParserDelegate {
    struct Item {
        var title = "", link = "", summary = "", author = "", image: String?
        var date: Date?
    }
    struct Feed { var title = ""; var items: [Item] = [] }

    private var feed = Feed()
    private var current: Item?
    private var text = ""

    static func parse(_ data: Data) -> Feed {
        let delegate = RSSParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.feed
    }

    private static let dateFormats = ["EEE, dd MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm:ss zzz", "dd MMM yyyy HH:mm:ss Z"]
    private static func date(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for format in dateFormats {
            f.dateFormat = format
            if let d = f.date(from: s.trimmingCharacters(in: .whitespacesAndNewlines)) { return d }
        }
        return nil
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String] = [:]) {
        text = ""
        if name == "item" { current = Item() }
        if name == "enclosure", current != nil, let url = attributes["url"],
           (attributes["type"] ?? "").hasPrefix("image") || current?.image == nil {
            current?.image = url
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        text += String(decoding: CDATABlock, as: UTF8.self)
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName qName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if current == nil {
            if name == "title", feed.title.isEmpty { feed.title = value }
            return
        }
        switch name {
        case "title": current?.title = HTML.decode(value)
        case "link": current?.link = value
        case "description": current?.summary = HTML.plainText(value).trimmingCharacters(in: .whitespaces)
        case "dc:creator", "creator": current?.author = value
        case "pubDate": current?.date = Self.date(value)
        case "item":
            if let item = current, !item.title.isEmpty { feed.items.append(item) }
            current = nil
        default: break
        }
        text = ""
    }
}
