import Foundation

/// Cinema listings from Clusterflick (clusterflick.com), which scrapes ~480 London venues several
/// times a day — including BFI Southbank, which blocks direct scraping — and publishes one JSON file.
///
/// FRAGILITY: low–medium. The file is a public build artifact with no schema promise.
/// If it breaks, check the field names below against a fresh download of DATA_URL.
enum ClusterflickSource {
    static let dataURL = URL(string: "https://github.com/clusterflick/data-combined/releases/latest/download/combined-data.json")!

    private struct Combined: Decodable {
        let generatedAt: String?
        let movies: [String: Movie]
        let venues: [String: Venue]
    }
    private struct Venue: Decodable {
        let id: String?
        let name: String?
    }
    private struct Movie: Decodable {
        let id: String
        let title: String
        let year: String?
        let posterPath: String?
        let duration: Int?          // milliseconds
        let performances: [Performance]?
        let showings: [String: Showing]?
    }
    private struct Performance: Decodable {
        let time: Double            // ms since epoch
        let bookingUrl: String?
        let showingId: String
        let screen: String?
        let status: Status?
    }
    private struct Status: Decodable { let soldOut: Bool? }
    private struct Showing: Decodable {
        let venueId: String
        let url: String?
        let title: String?
    }

    struct Output {
        var venues: [CinemaVenue]
        var catalogue: [CinemaVenueRef]
        var warnings: [String]
    }

    static func fetch(venueIDs: [String], days: Int = 8) async throws -> Output {
        guard !venueIDs.isEmpty else {
            throw FetchError.notConfigured("Pick some cinemas in Settings to see showtimes.")
        }
        let data = try await HTTP.data(from: dataURL, accept: "application/json")
        let combined = try JSONDecoder().decode(Combined.self, from: data)

        let cal = Calendar.london
        let windowStart = cal.startOfDay(for: Date())
        let windowEnd = cal.date(byAdding: .day, value: days, to: windowStart)!
        let wanted = Set(venueIDs)

        // venueId -> movieId -> Film
        var byVenue: [String: [String: Film]] = [:]
        for movie in combined.movies.values {
            let showings = movie.showings ?? [:]
            for p in movie.performances ?? [] {
                guard let showing = showings[p.showingId], wanted.contains(showing.venueId) else { continue }
                let time = Date(timeIntervalSince1970: p.time / 1000)
                guard time >= windowStart, time < windowEnd else { continue }

                let showtime = Showtime(id: "\(p.showingId)-\(Int(p.time))-\(p.screen ?? "")",
                                        time: time,
                                        bookingURL: p.bookingUrl.flatMap { URL(string: $0) },
                                        soldOut: p.status?.soldOut ?? false,
                                        screen: p.screen)
                if byVenue[showing.venueId]?[movie.id] == nil {
                    byVenue[showing.venueId, default: [:]][movie.id] = Film(
                        id: movie.id,
                        title: movie.title,
                        year: movie.year,
                        runtimeMinutes: movie.duration.map { $0 / 60_000 },
                        posterURL: movie.posterPath.flatMap { URL(string: "https://image.tmdb.org/t/p/w342\($0)") },
                        url: showing.url.flatMap { URL(string: $0) },
                        showtimes: [])
                }
                byVenue[showing.venueId]?[movie.id]?.showtimes.append(showtime)
            }
        }

        let catalogue = combined.venues.compactMap { key, v -> CinemaVenueRef? in
            guard let name = v.name else { return nil }
            return CinemaVenueRef(id: v.id ?? key, name: name)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let venues = venueIDs.map { id -> CinemaVenue in
            let name = combined.venues[id]?.name ?? Defaults.cinemas.first(where: { $0.id == id })?.name ?? id
            let films = (byVenue[id] ?? [:]).values.map { film -> Film in
                var f = film
                f.showtimes.sort { $0.time < $1.time }
                return f
            }.sorted { ($0.showtimes.first?.time ?? .distantFuture) < ($1.showtimes.first?.time ?? .distantFuture) }
            return CinemaVenue(id: id, name: name, films: films)
        }

        var warnings: [String] = []
        for v in venues where v.films.isEmpty {
            warnings.append("\(v.name): no screenings in the data this week.")
        }
        if let stamp = combined.generatedAt, let generated = ISO8601DateFormatter().date(from: stamp),
           Date().timeIntervalSince(generated) > 36 * 3600 {
            let days = Int(Date().timeIntervalSince(generated) / 86_400)
            warnings.append("Clusterflick's data is \(max(days, 1)) day\(days == 1 ? "" : "s") old.")
        }
        return Output(venues: venues, catalogue: catalogue, warnings: warnings)
    }
}
