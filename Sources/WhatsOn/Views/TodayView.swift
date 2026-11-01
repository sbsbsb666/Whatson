import SwiftUI

/// Overview: a few highlights from each section, each with "See All".
struct TodayView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.navigate) private var navigate

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                header
                cinemaToday
                gigsThisWeek
                exhibitionHighlights
                latestMixes
            }
            .padding(Layouts.pagePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Today")
        .navigationSubtitle(model.overallUpdatedLabel)
    }

    // MARK: Header

    private var greeting: String {
        let hour = Calendar.london.component(.hour, from: model.now)
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<18: return "Good afternoon"
        default: return "Good evening"
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Fmt.longDate.string(from: model.now).uppercased())
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(greeting)
                .font(.largeTitle.weight(.bold))
        }
    }

    // MARK: Cinema

    private struct Screening: Identifiable {
        let venue: String
        let film: Film
        let times: [Showtime]
        var id: String { venue + film.id }
    }

    private var screeningsToday: [Screening] {
        let cal = Calendar.london
        var result: [Screening] = []
        for venue in model.cinema.items {
            for film in venue.films {
                let times = film.showtimes.filter { cal.isDate($0.time, inSameDayAs: model.now) && $0.time > model.now }
                if !times.isEmpty { result.append(Screening(venue: venue.name, film: film, times: times)) }
            }
        }
        return result.sorted { $0.times[0].time < $1.times[0].time }
    }

    private var cinemaToday: some View {
        let screenings = Array(screeningsToday.prefix(12))
        return VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "At the cinema tonight",
                          subtitle: screenings.isEmpty ? nil : "Still to come today",
                          actionTitle: "See All") { navigate(.cinema) }
            if screenings.isEmpty {
                Placeholder(state: model.cinema, empty: "Nothing else showing today at your cinemas.")
            } else {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 18) {
                        ForEach(screenings) { s in
                            LinkButton(url: s.times.first?.bookingURL ?? s.film.url) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Artwork(url: s.film.posterURL, aspect: 2 / 3, symbol: "film", cornerRadius: 8)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(s.film.title).font(.headline).lineLimit(2).multilineTextAlignment(.leading)
                                        Text(s.venue).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        Text(s.times.prefix(3).map { Fmt.time.string(from: $0.time) }.joined(separator: "  "))
                                            .font(.caption.weight(.medium))
                                            .monospacedDigit()
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                                .frame(width: 140, alignment: .leading)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 2)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    // MARK: Gigs

    private var gigsThisWeek: some View {
        let cal = Calendar.london
        let weekEnd = cal.date(byAdding: .day, value: 7, to: cal.startOfDay(for: model.now))!
        let week = model.gigs.items.filter { $0.date < weekEnd }
        let next = model.gigs.items.first

        return VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Gigs this week", actionTitle: "See All") { navigate(.gigs) }
            if !week.isEmpty {
                LazyVGrid(columns: Layouts.gigCards, alignment: .leading, spacing: 14) {
                    ForEach(week.prefix(6)) { GigFeatureCard(gig: $0) }
                }
            } else if let next {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Nothing this week. Next up:").font(.callout).foregroundStyle(.secondary)
                    GigFeatureCard(gig: next).frame(maxWidth: 420)
                }
            } else {
                Placeholder(state: model.gigs, empty: "No upcoming London gigs from artists you track.")
            }
        }
    }

    // MARK: Exhibitions

    private var exhibitionHighlights: some View {
        let items = model.exhibitions.items
        let closing = items.filter { !$0.isOpeningSoon && ($0.daysUntilClose ?? 999) <= 14 }
            .sorted { ($0.endDate ?? .distantFuture) < ($1.endDate ?? .distantFuture) }
        let fresh = items.filter { ($0.daysSinceOpen.map { $0 >= 0 && $0 <= 14 } ?? false) || ($0.isOpeningSoon && ($0.startDate.map { Calendar.london.daysBetween(model.now, $0) <= 14 } ?? false)) }
            .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
        var picks = Array((closing + fresh).prefix(6))
        if picks.isEmpty {
            picks = Array(items.filter { !$0.isOpeningSoon }
                .sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
                .prefix(6))
        }
        var seen = Set<String>()
        picks = picks.filter { seen.insert($0.id).inserted }

        return VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Exhibitions",
                          subtitle: picks.isEmpty ? nil : "Closing soon and just opened",
                          actionTitle: "See All") { navigate(.exhibitions) }
            if picks.isEmpty {
                Placeholder(state: model.exhibitions, empty: "No current shows at your galleries.")
            } else {
                LazyVGrid(columns: Layouts.cards, alignment: .leading, spacing: 30) {
                    ForEach(picks) { ExhibitionCard(item: $0) }
                }
            }
        }
    }

    // MARK: Mixcloud

    private var latestMixes: some View {
        let mixes = Array(model.mixes.items.prefix(6))
        return VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "New on Mixcloud", actionTitle: "See All") { navigate(.mixcloud) }
            if mixes.isEmpty {
                Placeholder(state: model.mixes, empty: "No new uploads from people you follow.")
            } else {
                LazyVGrid(columns: Layouts.squares, alignment: .leading, spacing: 26) {
                    ForEach(mixes) { MixCard(mix: $0, now: model.now) }
                }
            }
        }
    }
}

/// Small inline state for a Today block with nothing to show.
private struct Placeholder<T: Codable>: View {
    let state: SectionState<T>
    let empty: String
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            if let setup = state.setupMessage {
                Image(systemName: "person.crop.circle.badge.plus").foregroundStyle(.secondary)
                Text(setup).foregroundStyle(.secondary)
                SettingsLink { Text("Open Settings…") }
                    .buttonStyle(.link)
            } else if state.isLoading && state.fetchedAt == nil {
                ProgressView().controlSize(.small)
                Text("Loading…").foregroundStyle(.secondary)
            } else if let error = state.error, state.items.isEmpty {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                Text("Couldn't load. \(error)").foregroundStyle(.secondary)
            } else {
                Text(empty).foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
