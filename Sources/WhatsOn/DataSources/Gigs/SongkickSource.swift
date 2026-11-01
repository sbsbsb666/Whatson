import Foundation

/// Gigs from a Songkick iCal calendar (or any other .ics link — Gigora, Bandsintown exports etc. also work).
///
/// FRAGILITY: low–medium. iCal is a stable format, but Songkick (owned by Suno since late 2025)
/// could change or retire the export. If it breaks, paste any other gig calendar link in Settings.
enum SongkickSource {
    static func candidateURLs(username: String, calendarLink: String) -> [URL] {
        let link = calendarLink.trimmingCharacters(in: .whitespacesAndNewlines)
        if !link.isEmpty {
            let fixed = link.lowercased().hasPrefix("webcal://") ? "https://" + String(link.dropFirst("webcal://".count)) : link
            return URL(string: fixed).map { [$0] } ?? []
        }
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        guard !user.isEmpty else { return [] }
        return [
            "https://www.songkick.com/users/\(user)/calendars.ics?filter=tracked_artist",
            "https://www.songkick.com/users/\(user)/calendars.ics"
        ].compactMap(URL.init(string:))
    }

    static func fetch(username: String, calendarLink: String, londonOnly: Bool) async throws -> SourceResult<Gig> {
        let urls = candidateURLs(username: username, calendarLink: calendarLink)
        guard !urls.isEmpty else {
            throw FetchError.notConfigured("Add your Songkick username or calendar link in Settings to see gigs.")
        }

        var lastError: Error = FetchError.parse("Couldn't read the Songkick calendar.")
        for url in urls {
            do {
                let data = try await HTTP.data(from: url, accept: "text/calendar,*/*;q=0.5")
                let text = String(decoding: data, as: UTF8.self)
                guard text.contains("BEGIN:VCALENDAR") else {
                    throw FetchError.parse("Songkick didn't return a calendar. Check the username, or paste your calendar link in Settings.")
                }
                let today = Calendar.london.startOfDay(for: Date())
                var seen = Set<String>()
                let gigs = ICalParser.parse(text)
                    .filter { !londonOnly || isLondon($0) }
                    .compactMap(gig(from:))
                    .filter { $0.date >= today && seen.insert($0.id).inserted }
                    .sorted { $0.date < $1.date }
                return SourceResult(items: gigs)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private static func isLondon(_ e: ICalEvent) -> Bool {
        let haystack = "\(e.location) \(e.summary)".lowercased()
        return haystack.contains("london")
    }

    static func gig(from e: ICalEvent) -> Gig? {
        guard let start = e.start else { return nil }
        var summary = e.summary.trimmingCharacters(in: .whitespaces)
        // Songkick summaries look like "Artist at Venue (06 Nov 26)"
        if let r = summary.range(of: #"\s*\([^()]*\)\s*$"#, options: .regularExpression) { summary.removeSubrange(r) }

        var artist = summary
        var venue = ""
        if let r = summary.range(of: " at ", options: .backwards) {
            artist = String(summary[..<r.lowerBound])
            venue = String(summary[r.upperBound...])
        }
        if venue.isEmpty {
            venue = e.location.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        }
        let url = e.url.flatMap { URL(string: $0) } ?? firstURL(in: e.description)
        let id = e.uid.isEmpty ? "\(artist)-\(start.timeIntervalSince1970)" : e.uid
        return Gig(id: id, artist: artist, venue: venue, location: e.location, date: start, allDay: e.allDay, url: url)
    }

    private static func firstURL(in text: String) -> URL? {
        HTML.firstMatch(#"(https?://[^\s"<>]+)"#, in: text).flatMap { URL(string: $0[0]) }
    }
}
