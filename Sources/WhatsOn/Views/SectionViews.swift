import SwiftUI

// MARK: - Exhibitions

struct ExhibitionsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var search = ""
    @State private var venue = "All"

    private var venues: [String] {
        ["All"] + Set(model.exhibitions.items.map(\.venue)).sorted()
    }

    private var filtered: [Exhibition] {
        model.exhibitions.items.filter { item in
            (venue == "All" || item.venue == venue) &&
            (search.isEmpty || item.title.localizedCaseInsensitiveContains(search) || item.venue.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        SectionPage(title: "Exhibitions", symbol: Destination.exhibitions.symbol, state: model.exhibitions,
                    retry: { Task { await model.refreshExhibitions() } }) {
            let items = filtered
            let onNow = items.filter { !$0.isOpeningSoon }
                .sorted { ($0.endDate ?? .distantFuture) < ($1.endDate ?? .distantFuture) }
            let soon = items.filter(\.isOpeningSoon)
                .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }

            if items.isEmpty {
                ContentUnavailableView.search(text: search)
            }
            if !onNow.isEmpty {
                grid("On now", "Closing soonest first", onNow)
            }
            if !soon.isEmpty {
                grid("Opening soon", nil, soon)
            }
        }
        .navigationTitle("Exhibitions")
        .navigationSubtitle(model.updatedLabel(model.exhibitions))
        .searchable(text: $search, placement: .toolbar, prompt: "Search exhibitions")
        .toolbar {
            ToolbarItem {
                Picker("Venue", selection: $venue) {
                    ForEach(venues, id: \.self) { Text($0 == "All" ? "All Venues" : $0).tag($0) }
                }
                .pickerStyle(.menu)
                .help("Filter by venue")
            }
        }
    }

    private func grid(_ title: String, _ subtitle: String?, _ items: [Exhibition]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: title, subtitle: subtitle ?? "\(items.count) show\(items.count == 1 ? "" : "s")")
            LazyVGrid(columns: Layouts.cards, alignment: .leading, spacing: 30) {
                ForEach(items) { ExhibitionCard(item: $0) }
            }
        }
    }
}

// MARK: - Gigs

struct GigsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var search = ""

    private var filtered: [Gig] {
        guard !search.isEmpty else { return model.gigs.items }
        return model.gigs.items.filter {
            $0.artist.localizedCaseInsensitiveContains(search) || $0.venue.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        SectionPage(title: "Gigs", symbol: Destination.gigs.symbol, state: model.gigs,
                    retry: { Task { await model.refreshGigs() } }) {
            let items = filtered
            let cal = Calendar.london
            let weekEnd = cal.date(byAdding: .day, value: 7, to: cal.startOfDay(for: model.now))!
            let thisWeek = items.filter { $0.date < weekEnd }
            let later = items.filter { $0.date >= weekEnd }
            let months = Dictionary(grouping: later) { cal.dateInterval(of: .month, for: $0.date)?.start ?? $0.date }
            let monthKeys = months.keys.sorted()

            if items.isEmpty {
                ContentUnavailableView.search(text: search)
            }
            if !thisWeek.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeader(title: "This week", subtitle: "\(thisWeek.count) gig\(thisWeek.count == 1 ? "" : "s")")
                    LazyVGrid(columns: Layouts.gigCards, alignment: .leading, spacing: 14) {
                        ForEach(thisWeek) { GigFeatureCard(gig: $0) }
                    }
                }
            }
            ForEach(monthKeys, id: \.self) { month in
                let gigs = months[month] ?? []
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: Fmt.monthYear.string(from: month))
                    GroupedBox {
                        ForEach(Array(gigs.enumerated()), id: \.element.id) { index, gig in
                            GigRow(gig: gig)
                            if index < gigs.count - 1 { Divider().padding(.leading, 76) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Gigs")
        .navigationSubtitle(model.updatedLabel(model.gigs))
        .searchable(text: $search, placement: .toolbar, prompt: "Search artists or venues")
    }
}

// MARK: - Mixcloud

struct MixcloudView: View {
    @EnvironmentObject private var model: AppModel
    @State private var search = ""

    private var filtered: [Mix] {
        guard !search.isEmpty else { return model.mixes.items }
        return model.mixes.items.filter {
            $0.title.localizedCaseInsensitiveContains(search) || $0.uploader.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        SectionPage(title: "Mixcloud", symbol: Destination.mixcloud.symbol, state: model.mixes,
                    retry: { Task { await model.refreshMixes() } }) {
            let items = filtered
            let cutoff = model.now.addingTimeInterval(-7 * 86_400)
            let recent = items.filter { $0.date >= cutoff }
            let earlier = items.filter { $0.date < cutoff }

            if items.isEmpty {
                ContentUnavailableView.search(text: search)
            }
            if !recent.isEmpty { grid("This week", recent) }
            if !earlier.isEmpty { grid("Earlier", earlier) }
        }
        .navigationTitle("Mixcloud")
        .navigationSubtitle(model.updatedLabel(model.mixes))
        .searchable(text: $search, placement: .toolbar, prompt: "Search mixes")
    }

    private func grid(_ title: String, _ items: [Mix]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: title, subtitle: "\(items.count) upload\(items.count == 1 ? "" : "s")")
            LazyVGrid(columns: Layouts.squares, alignment: .leading, spacing: 26) {
                ForEach(items) { MixCard(mix: $0, now: model.now) }
            }
        }
    }
}

// MARK: - Cinema

struct CinemaView: View {
    @EnvironmentObject private var model: AppModel
    @State private var dayOffset = 0
    @State private var search = ""

    private var days: [Date] {
        let cal = Calendar.london
        let today = cal.startOfDay(for: model.now)
        return (0..<8).compactMap { cal.date(byAdding: .day, value: $0, to: today) }
    }

    var body: some View {
        SectionPage(title: "Cinema", symbol: Destination.cinema.symbol, state: model.cinema,
                    retry: { Task { await model.refreshCinema() } }) {
            DayPicker(days: days, selection: $dayOffset)
            let day = days[min(dayOffset, days.count - 1)]
            ForEach(model.cinema.items) { venue in
                VenueSection(venue: venue, day: day, search: search, now: model.now)
            }
        }
        .navigationTitle("Cinema")
        .navigationSubtitle(model.updatedLabel(model.cinema))
        .searchable(text: $search, placement: .toolbar, prompt: "Search films")
    }
}

struct DayPicker: View {
    let days: [Date]
    @Binding var selection: Int

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(days.indices, id: \.self) { i in
                    let selected = i == selection
                    Button {
                        withAnimation(.snappy(duration: 0.25)) { selection = i }
                    } label: {
                        VStack(spacing: 1) {
                            Text(i == 0 ? "Today" : i == 1 ? "Tomorrow" : Fmt.weekdayShort.string(from: days[i]))
                                .font(.caption.weight(.medium))
                            Text(Fmt.dayNumber.string(from: days[i]))
                                .font(.title3.weight(.semibold))
                                .monospacedDigit()
                        }
                        .frame(width: 76, height: 52)
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(selected ? Color.accentColor : Color.primary.opacity(0.05))
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }
}

struct VenueSection: View {
    let venue: CinemaVenue
    let day: Date
    let search: String
    let now: Date

    private var films: [(film: Film, times: [Showtime])] {
        let cal = Calendar.london
        return venue.films.compactMap { film -> (film: Film, times: [Showtime])? in
            guard search.isEmpty || film.title.localizedCaseInsensitiveContains(search) else { return nil }
            let times = film.showtimes.filter { cal.isDate($0.time, inSameDayAs: day) }
            if times.isEmpty { return nil }
            return (film: film, times: times)
        }
        .sorted { $0.times[0].time < $1.times[0].time }
    }

    var body: some View {
        let list = films
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: venue.name,
                          subtitle: list.isEmpty ? "No screenings listed" : "\(list.count) film\(list.count == 1 ? "" : "s")")
            if !list.isEmpty {
                GroupedBox {
                    ForEach(Array(list.enumerated()), id: \.element.film.id) { index, entry in
                        FilmRow(film: entry.film, times: entry.times, now: now)
                        if index < list.count - 1 { Divider().padding(.leading, 84) }
                    }
                }
            }
        }
    }
}
