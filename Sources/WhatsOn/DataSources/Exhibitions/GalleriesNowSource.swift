import Foundation

/// Reads a GalleriesNow listing page — usually https://www.galleriesnow.net/exhibitions/london-west-end,
/// which lists every West End gallery show (Zwirner, Hauser & Wirth, Pace, Ropac, Sprüth Magers…) on one page.
/// Everything needed (image, title, gallery, dates, address) is in the listing, so it's a single request.
///
/// Each show on the page is a block like:
///   <a href="/shows/<slug>/"><img alt="Image for <Title>, at <Gallery>" src="…webp"></a>
///   <a href="/gallery/<gallery>/">Gallery</a> London West End
///   <a href="/shows/<slug>/">Title</a>  Fri 9 Oct - Sat 14 Nov 2026  22 Cork Street, W1S 3NG, London
///
/// `filter` (comma-separated) keeps only matching shows: postcode districts like "W1S, SW1Y",
/// or any other words, matched against the gallery name and block text (e.g. "Zwirner, Hauser").
///
/// FRAGILITY: medium. If it breaks, check that show links still look like /shows/<slug>/ and the
/// main image still has alt="Image for <Title>, at <Gallery>".
enum GalleriesNowSource {
    /// One block on the page. `exhibition` is nil for blocks with no usable dates (e.g. auctions).
    struct Show {
        let gallery: String
        let postcode: String
        let text: String
        let exhibition: Exhibition?
    }

    /// Any GalleriesNow listing page, filtered by `filter` (postcode districts and/or gallery names).
    static func fetch(listing: URL, filter: String, fallbackVenue: String) async throws -> [Exhibition] {
        let rules = Rules(filter)
        return try await shows(at: listing, fallbackVenue: fallbackVenue)
            .filter { rules.matches(text: $0.text, gallery: $0.gallery) }
            .compactMap(\.exhibition)
    }

    /// The West End page: shows from the galleries you've ticked, plus the full list of galleries on it.
    static func fetchWestEnd(selected: [String]) async throws -> (items: [Exhibition], catalogue: [WestEndGallery]) {
        let all = try await shows(at: Defaults.westEndURL, fallbackVenue: "West End")
        let wanted = Set(selected.map(normalise))
        let items = all.filter { wanted.contains(normalise($0.gallery)) }.compactMap(\.exhibition)

        var seen = Set<String>()
        var catalogue: [WestEndGallery] = []
        for show in all where !show.gallery.isEmpty && !show.gallery.lowercased().contains("sotheby") {
            if seen.insert(show.gallery).inserted {
                catalogue.append(WestEndGallery(name: show.gallery, postcode: show.postcode))
            }
        }
        catalogue.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return (items, catalogue)
    }

    private static func normalise(_ s: String) -> String {
        s.lowercased().trimmingCharacters(in: .whitespaces)
    }

    private static func shows(at listing: URL, fallbackVenue: String) async throws -> [Show] {
        let html = try await HTTP.text(from: listing)
        let ns = html as NSString
        guard let showLink = try? NSRegularExpression(
            pattern: #"href\s*=\s*["'](?:https?://(?:www\.)?galleriesnow\.net)?/shows/([a-z0-9][a-z0-9\-]*)/?["']"#,
            options: .caseInsensitive) else { return [] }

        // Split the page into one block per show: a new block starts whenever the show slug changes.
        var starts: [(slug: String, location: Int)] = []
        for m in showLink.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let slug = ns.substring(with: m.range(at: 1))
            if starts.last?.slug != slug { starts.append((slug: slug, location: m.range.location)) }
        }
        guard !starts.isEmpty else { throw FetchError.parse("GalleriesNow's page layout has changed — no shows found.") }

        var results: [Show] = []
        for (i, start) in starts.enumerated() {
            let end = i + 1 < starts.count ? starts[i + 1].location : min(ns.length, start.location + 20_000)
            let chunk = ns.substring(with: NSRange(location: start.location, length: max(0, end - start.location)))
            results.append(parse(chunk: chunk, slug: start.slug, fallbackVenue: fallbackVenue))
        }
        return results
    }

    private static func parse(chunk: String, slug: String, fallbackVenue: String) -> Show {
        let text = HTML.plainText("<a " + chunk)

        var title = ""
        var gallery = ""
        if let alt = HTML.firstMatch(#"alt\s*=\s*"Image for ([^"]+)""#, in: chunk)?.first {
            let decoded = HTML.decode(alt)
            if let r = decoded.range(of: ", at ", options: .backwards) {
                title = String(decoded[..<r.lowerBound])
                gallery = String(decoded[r.upperBound...])
            } else {
                title = decoded
            }
        }
        if gallery.isEmpty, let g = HTML.firstMatch(#"/gallery/[^"']+["'][^>]*>\s*([^<]+?)\s*<"#, in: chunk) {
            gallery = HTML.decode(g[0])
        }
        if title.isEmpty,
           let t = HTML.firstMatch(#"/shows/"# + NSRegularExpression.escapedPattern(for: slug) + #"/?["'][^>]*>\s*([^<]+?)\s*<"#, in: chunk) {
            title = HTML.decode(t[0])
        }
        title = title.trimmingCharacters(in: .whitespaces)
        gallery = gallery.trimmingCharacters(in: .whitespaces)
        let postcode = HTML.firstMatch(#"\b([A-Z]{1,2}\d[A-Z\d]?)\s*\d[A-Z]{2}\b"#, in: text, options: [])?.first ?? ""

        var exhibition: Exhibition?
        let isAuction = text.range(of: "auction", options: .caseInsensitive) != nil
        if !isAuction, !title.isEmpty, let span = DateText.span(in: text), span.end != nil,
           let url = URL(string: "https://www.galleriesnow.net/shows/\(slug)/") {
            exhibition = Exhibition(id: url.absoluteString, title: title,
                                    venue: gallery.isEmpty ? fallbackVenue : gallery,
                                    startDate: span.start, endDate: span.end,
                                    imageURL: mainImage(in: chunk), url: url)
        }
        return Show(gallery: gallery, postcode: postcode, text: text, exhibition: exhibition)
    }

    /// The show image (the one whose alt starts "Image for"), handling lazy-loading attributes.
    private static func mainImage(in chunk: String) -> URL? {
        let tags = HTML.allMatches(#"(<img\b[^>]*>)"#, in: chunk).map { $0[0] }
        guard let tag = tags.first(where: { $0.contains("Image for") }) ?? tags.first(where: { !$0.lowercased().contains("logo") }) else { return nil }
        for attr in ["data-lazy-src", "data-src", "src"] {
            if let v = HTML.firstMatch(#"\b"# + attr + #"\s*=\s*"([^"]+)""#, in: tag)?.first,
               !v.hasPrefix("data:"), let u = URL(string: HTML.decode(v)) { return u }
        }
        if let set = HTML.firstMatch(#"\b(?:data-)?srcset\s*=\s*"([^"\s,]+)"#, in: tag)?.first {
            return URL(string: HTML.decode(set))
        }
        return nil
    }

    private struct Rules {
        var postcodes: [String] = []
        var words: [String] = []

        init(_ filter: String) {
            for raw in filter.split(separator: ",") {
                let token = raw.trimmingCharacters(in: .whitespaces)
                guard !token.isEmpty else { continue }
                if token.range(of: #"^[A-Za-z]{1,2}\d[A-Za-z\d]?$"#, options: .regularExpression) != nil {
                    postcodes.append(token.uppercased())
                } else {
                    words.append(token)
                }
            }
        }

        func matches(text: String, gallery: String) -> Bool {
            if postcodes.isEmpty && words.isEmpty { return true }
            for p in postcodes where HTML.firstMatch(#"\b"# + p + #"\s*\d[A-Z]{2}\b"#, in: text) != nil { return true }
            for w in words {
                let pattern = #"(?<![\w])"# + NSRegularExpression.escapedPattern(for: w) + #"(?![\w])"#
                if HTML.firstMatch(pattern, in: gallery) != nil { return true }
            }
            return false
        }
    }
}
