import Foundation

/// Scrapes an ArtRabbit organisation page (e.g. artrabbit.com/organisations/south-london-gallery).
///
/// FRAGILITY: medium. If ArtRabbit changes its markup, the things to check are:
///   1. event links on the organisation page still look like  href="/events/<slug>"
///   2. event pages still carry og:title "<Title> - Exhibition at <Venue> in London" and og:image
///   3. dates still appear as "10 Sep 2026 – 22 Nov 2026"
enum ArtRabbitSource {
    static func fetch(organisation: URL, venue: String) async throws -> [Exhibition] {
        var components = URLComponents(url: organisation, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        if components?.queryItems?.isEmpty ?? true {
            components?.queryItems = [URLQueryItem(name: "view", value: "cur")]   // current + upcoming
        }
        let html = try await HTTP.text(from: components?.url ?? organisation)

        // Ignore the "associated exhibitions" block further down the page (other venues' shows).
        var listing = html
        if let cut = html.range(of: "id=\"associations\"") ?? html.range(of: "id='associations'") {
            listing = String(html[..<cut.lowerBound])
        }

        var seen = Set<String>()
        var slugs: [String] = []
        for g in HTML.allMatches(#"href\s*=\s*["'](?:https?://(?:www\.)?artrabbit\.com)?/events/([a-z0-9][a-z0-9\-]*)"#, in: listing)
        where seen.insert(g[0]).inserted {
            slugs.append(g[0])
        }

        let found = await boundedMap(Array(slugs.prefix(12)), limit: 4) { slug -> Exhibition? in
            (try? await event(slug: slug, venue: venue)) ?? nil
        }
        return found.compactMap { $0 }
    }

    static func event(slug: String, venue: String) async throws -> Exhibition? {
        guard let url = URL(string: "https://www.artrabbit.com/events/\(slug)") else { return nil }
        let html = try await HTTP.text(from: url)

        let rawTitle = HTML.meta(html, "og:title") ?? HTML.title(html) ?? ""
        // Only exhibitions — skip talks, workshops and other events.
        guard let marker = rawTitle.range(of: " - Exhibition at ", options: .caseInsensitive) else { return nil }
        let title = String(rawTitle[..<marker.lowerBound]).trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }

        let image = (HTML.meta(html, "og:image") ?? HTML.meta(html, "twitter:image:src")).flatMap { URL(string: $0) }
        let span = DateText.span(in: HTML.plainText(html))

        // Prefer the gallery's own page ("Event website" link) when there is one.
        var link = url
        if let g = HTML.firstMatch(#"<a\b[^>]*href\s*=\s*"(https?://[^"]+)"[^>]*>(?:(?!</a>)[\s\S]){0,400}?Event website"#, in: html),
           let external = URL(string: HTML.decode(g[0])),
           external.host?.contains("artrabbit") == false {
            link = external
        }

        return Exhibition(id: url.absoluteString, title: title, venue: venue,
                          startDate: span?.start, endDate: span?.end, imageURL: image, url: link)
    }
}
