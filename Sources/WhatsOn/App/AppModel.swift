import SwiftUI
import Combine

/// Owns the four sections. Each refreshes independently, so one failing never blocks the others.
@MainActor
final class AppModel: ObservableObject {
    @Published var exhibitions: SectionState<Exhibition>
    @Published var gigs: SectionState<Gig>
    @Published var mixes: SectionState<Mix>
    @Published var cinema: SectionState<CinemaVenue>
    /// Ticks every minute so "Updated 5 minutes ago" stays fresh.
    @Published var now = Date()

    let settings: SettingsStore
    private var bag = Set<AnyCancellable>()
    private var started = false

    init(settings: SettingsStore) {
        self.settings = settings
        exhibitions = SectionState(snapshot: Cache.load("exhibitions"))
        gigs = SectionState(snapshot: Cache.load("gigs"))
        mixes = SectionState(snapshot: Cache.load("mixcloud"))
        cinema = SectionState(snapshot: Cache.load("cinema"))

        Timer.publish(every: 60, on: .main, in: .common).autoconnect()
            .sink { [weak self] date in self?.now = date }
            .store(in: &bag)

        // Refresh a section shortly after its settings change.
        settings.$songkickUsername.combineLatest(settings.$songkickICalURL, settings.$londonOnly)
            .dropFirst().debounce(for: .seconds(1.5), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.refreshGigs() }
            }
            .store(in: &bag)
        settings.$mixcloudUsername
            .dropFirst().debounce(for: .seconds(1.5), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.refreshMixes() }
            }
            .store(in: &bag)
        settings.$galleries
            .dropFirst().debounce(for: .seconds(3), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.refreshExhibitions() }
            }
            .store(in: &bag)
        settings.$cinemaVenueIDs
            .dropFirst().debounce(for: .seconds(1.5), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.refreshCinema() }
            }
            .store(in: &bag)
    }

    func start() {
        guard !started else { return }
        started = true
        refreshAll()
        Task.detached(priority: .background) { Cache.pruneImages() }
    }

    var isRefreshing: Bool {
        exhibitions.isLoading || gigs.isLoading || mixes.isLoading || cinema.isLoading
    }

    func refreshAll() {
        Task { await refreshExhibitions() }
        Task { await refreshGigs() }
        Task { await refreshMixes() }
        Task { await refreshCinema() }
    }

    func refreshExhibitions() async {
        let galleries = settings.galleries
        await run(\.exhibitions, key: "exhibitions") {
            try await ExhibitionsSource.fetch(galleries: galleries)
        }
    }

    func refreshGigs() async {
        let user = settings.songkickUsername, link = settings.songkickICalURL, london = settings.londonOnly
        await run(\.gigs, key: "gigs") {
            try await SongkickSource.fetch(username: user, calendarLink: link, londonOnly: london)
        }
    }

    func refreshMixes() async {
        let user = settings.mixcloudUsername
        await run(\.mixes, key: "mixcloud") {
            try await MixcloudSource.fetch(username: user)
        }
    }

    func refreshCinema() async {
        let ids = settings.cinemaVenueIDs
        await run(\.cinema, key: "cinema") { [settings] in
            let output = try await ClusterflickSource.fetch(venueIDs: ids)
            if !output.catalogue.isEmpty { settings.knownCinemaVenues = output.catalogue }
            return SourceResult(items: output.venues, warnings: output.warnings)
        }
    }

    private func run<T: Codable>(_ keyPath: ReferenceWritableKeyPath<AppModel, SectionState<T>>,
                                 key: String,
                                 _ operation: () async throws -> SourceResult<T>) async {
        guard !self[keyPath: keyPath].isLoading else { return }
        self[keyPath: keyPath].isLoading = true

        var state = self[keyPath: keyPath]
        do {
            let result = try await operation()
            let fetched = Date()
            state.items = result.items
            state.warnings = result.warnings
            state.fetchedAt = fetched
            state.error = nil
            state.setupMessage = nil
            Cache.save(Snapshot(items: result.items, fetchedAt: fetched, warnings: result.warnings), key: key)
        } catch FetchError.notConfigured(let message) {
            state.items = []
            state.warnings = []
            state.error = nil
            state.setupMessage = message
        } catch {
            state.error = describe(error)
        }
        state.isLoading = false
        withAnimation(.easeInOut(duration: 0.25)) {
            self[keyPath: keyPath] = state
        }
    }

    // MARK: - Labels

    func updatedLabel<T>(_ state: SectionState<T>) -> String {
        if state.isLoading { return "Updating…" }
        guard let date = state.fetchedAt else { return state.setupMessage != nil ? "Not set up" : "Not loaded yet" }
        return "Updated " + relative(date)
    }

    var overallUpdatedLabel: String {
        if isRefreshing { return "Updating…" }
        let dates = [exhibitions.fetchedAt, gigs.fetchedAt, mixes.fetchedAt, cinema.fetchedAt].compactMap { $0 }
        guard let oldest = dates.min() else { return "London" }
        return "London · Updated " + relative(oldest)
    }

    func relative(_ date: Date?) -> String {
        guard let date else { return "never" }
        if now.timeIntervalSince(date) < 60 { return "just now" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        f.locale = Locale(identifier: "en_GB")
        return f.localizedString(for: date, relativeTo: now)
    }
}
