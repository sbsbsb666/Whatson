import Foundation

/// Fallback scraper for a gallery's own "what's on" page (used for Tate).
/// Finds links that start with `linkPrefix`, then reads og:title / og:image and the first date range on each page.
///
/// FRAGILITY: high. Works on most sites with sensible URLs and Open Graph tags, but any redesign can break it.
/// If a gallery stops loading, check the listing page still links to exhibitions under the same path prefix.
enum GenericGallerySource {
    static func fetch(listing: URL, linkPrefix: String, venue: String) async throws -> [Exhibition] {
        let html = try await HTTP.text(from: listing)

        var prefix = linkPrefix.trimmingCharacters(in: .whitespaces)
        if prefix.isEmpty { prefix = listing.path }
        if !prefix.hasPrefix("/") { prefix = "/" + prefix }
        if !prefix.hasSuffix("/") { prefix += "/" }

        let host = bareHost(listing)
        var seen = Set<String>()
        var pages: [URL] = []
        for link in HTML.links(in: html, base: listing) {
            guard bareHost(link) == host,
                  link.path.hasPrefix(prefix) || (link.path + "/").hasPrefix(prefix),
                  link.path.count > prefix.count + 1 else { continue }
            var c = URLComponents(url: link, resolvingAgainstBaseURL: false)
            c?.query = nil
            c?.fragment = nil
            guard let clean = c?.url, seen.insert(clean.path).inserted else { continue }
            pages.append(clean)
        }

        let found = await boundedMap(Array(pages.prefix(16)), limit: 4) { page -> Exhibition? in
            (try? await exhibition(at: page, venue: venue)) ?? nil
        }
        return found.compactMap { $0 }
    }

    static func exhibition(at url: URL, venue: String) async throws -> Exhibition? {
        let html = try await HTTP.text(from: url)
        // No date range → probably not an exhibition page (a talk, a tour, a collection display).
        guard let span = DateText.span(in: HTML.plainText(html)), span.end != nil else { return nil }

        var title = HTML.meta(html, "og:title") ?? HTML.title(html) ?? ""
        if let r = title.range(of: " | ", options: .backwards) { title = String(title[..<r.lowerBound]) }
        let brand = venue.split(separator: " ").first.map { $0.lowercased() } ?? ""
        for sep in [" – ", " — ", " - "] {
            if let r = title.range(of: sep, options: .backwards),
               title[r.upperBound...].lowercased().contains(brand) {
                title = String(title[..<r.lowerBound])
            }
        }
        title = title.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }

        let image = HTML.meta(html, "og:image").flatMap { URL(string: $0, relativeTo: url)?.absoluteURL }
        return Exhibition(id: url.absoluteString, title: title, venue: venue,
                          startDate: span.start, endDate: span.end, imageURL: image, url: url)
    }

    private static func bareHost(_ url: URL) -> String {
        let h = url.host?.lowercased() ?? ""
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }
}
