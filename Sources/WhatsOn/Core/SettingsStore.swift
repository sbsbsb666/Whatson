import Foundation
import Combine

enum Defaults {
    /// ArtRabbit organisation pages share one layout, so they're far sturdier than scraping each gallery's own site.
    /// Tate isn't on ArtRabbit, so it uses the generic page scraper with a link prefix.
    static let galleries: [GalleryConfig] = [
        GalleryConfig(name: "South London Gallery", url: "https://www.artrabbit.com/organisations/south-london-gallery"),
        GalleryConfig(name: "Whitechapel Gallery", url: "https://www.artrabbit.com/organisations/whitechapel-gallery"),
        GalleryConfig(name: "Camden Art Centre", url: "https://www.artrabbit.com/organisations/camden-art-centre"),
        GalleryConfig(name: "ICA", url: "https://www.artrabbit.com/organisations/ica-institute-of-contemporary-arts"),
        GalleryConfig(name: "Serpentine North", url: "https://www.artrabbit.com/organisations/serpentine-north-gallery"),
        GalleryConfig(name: "Hayward Gallery", url: "https://www.artrabbit.com/organisations/hayward-gallery"),
        GalleryConfig(name: "Barbican", url: "https://www.artrabbit.com/organisations/barbican-centre"),
        GalleryConfig(name: "Chisenhale Gallery", url: "https://www.artrabbit.com/organisations/chisenhale-gallery"),
        GalleryConfig(name: "Gasworks", url: "https://www.artrabbit.com/organisations/gasworks"),
        GalleryConfig(name: "White Cube Bermondsey", url: "https://www.artrabbit.com/organisations/white-cube-bermondsey"),
        GalleryConfig(name: "Lisson Gallery", url: "https://www.artrabbit.com/organisations/lisson-gallery-67-lisson-street"),
        GalleryConfig(name: "Tate Modern", url: "https://www.tate.org.uk/whats-on/tate-modern", linkPrefix: "/whats-on/tate-modern/"),
        GalleryConfig(name: "Tate Britain", url: "https://www.tate.org.uk/whats-on/tate-britain", linkPrefix: "/whats-on/tate-britain/"),
        // Private galleries around Grafton Street: every West End show on GalleriesNow, kept to
        // Mayfair (W1S, W1J, W1K), Hanover Sq / Regent St (W1B) and St James's (SW1Y).
        GalleryConfig(name: "Mayfair & St James’s", url: "https://www.galleriesnow.net/exhibitions/london-west-end",
                      filter: "W1S, W1J, W1K, W1B, SW1Y"),
        GalleryConfig(name: "Lisson Gallery Cork Street", url: "https://www.artrabbit.com/organisations/lisson-gallery-22-cork-street")
    ]

    /// Defaults from the first release. Anything in `galleries` not listed here is "new" and gets
    /// added to existing installs once (and stays removed if you delete it).
    static let firstReleaseGalleryURLs: Set<String> = Set(galleries.prefix(13).map(\.url))

    static let cinemas: [CinemaVenueRef] = [
        CinemaVenueRef(id: "everymancinema.com-crystal-palace", name: "Everyman Crystal Palace"),
        CinemaVenueRef(id: "bfi.org.uk-southbank", name: "BFI Southbank"),
        CinemaVenueRef(id: "barbican.org.uk", name: "Barbican Cinema")
    ]
}

/// User settings, persisted in UserDefaults.
final class SettingsStore: ObservableObject {
    private static let store = UserDefaults.standard

    @Published var songkickUsername: String { didSet { Self.store.set(songkickUsername, forKey: "songkickUsername") } }
    @Published var songkickICalURL: String { didSet { Self.store.set(songkickICalURL, forKey: "songkickICalURL") } }
    @Published var londonOnly: Bool { didSet { Self.store.set(londonOnly, forKey: "londonOnly") } }
    @Published var mixcloudUsername: String { didSet { Self.store.set(mixcloudUsername, forKey: "mixcloudUsername") } }
    @Published var galleries: [GalleryConfig] { didSet { Self.save(galleries, "galleries") } }
    @Published var cinemaVenueIDs: [String] { didSet { Self.store.set(cinemaVenueIDs, forKey: "cinemaVenueIDs") } }
    @Published var knownCinemaVenues: [CinemaVenueRef] { didSet { Self.save(knownCinemaVenues, "knownCinemaVenues") } }

    // Updates
    @Published var updateRepo: String { didSet { Self.store.set(updateRepo, forKey: "updateRepo") } }
    @Published var updateBranch: String { didSet { Self.store.set(updateBranch, forKey: "updateBranch") } }
    @Published var autoCheckUpdates: Bool { didSet { Self.store.set(autoCheckUpdates, forKey: "autoCheckUpdates") } }

    init() {
        let d = Self.store
        songkickUsername = d.string(forKey: "songkickUsername") ?? ""
        songkickICalURL = d.string(forKey: "songkickICalURL") ?? ""
        londonOnly = d.object(forKey: "londonOnly") as? Bool ?? true
        mixcloudUsername = d.string(forKey: "mixcloudUsername") ?? ""
        cinemaVenueIDs = d.stringArray(forKey: "cinemaVenueIDs") ?? Defaults.cinemas.map(\.id)
        knownCinemaVenues = Self.load("knownCinemaVenues") ?? Defaults.cinemas

        // The repo the app was built from is baked into Info.plist by build.sh.
        let bakedRepo = Bundle.main.object(forInfoDictionaryKey: "WORepo") as? String ?? ""
        let bakedBranch = Bundle.main.object(forInfoDictionaryKey: "WOBranch") as? String ?? ""
        let savedRepo = d.string(forKey: "updateRepo") ?? ""
        updateRepo = savedRepo.isEmpty ? bakedRepo : savedRepo
        let savedBranch = d.string(forKey: "updateBranch") ?? ""
        updateBranch = !savedBranch.isEmpty ? savedBranch : (bakedBranch.isEmpty || bakedBranch == "HEAD" ? "main" : bakedBranch)
        autoCheckUpdates = d.object(forKey: "autoCheckUpdates") as? Bool ?? true

        // Galleries: keep the user's list, and add any defaults introduced since they last ran the app.
        let saved: [GalleryConfig]? = Self.load("galleries")
        var list = saved ?? Defaults.galleries
        let offeredSaved: Set<String>? = d.stringArray(forKey: "offeredDefaultGalleryURLs").map { Set($0) }
        let offered = offeredSaved ?? (saved == nil ? Set(Defaults.galleries.map(\.url)) : Defaults.firstReleaseGalleryURLs)
        let existing = Set(list.map(\.url))
        for g in Defaults.galleries where !offered.contains(g.url) && !existing.contains(g.url) {
            list.append(g)
        }
        galleries = list
        Self.save(list, "galleries")
        d.set(Array(offered.union(Defaults.galleries.map(\.url))), forKey: "offeredDefaultGalleryURLs")
    }

    func cinemaName(for id: String) -> String {
        knownCinemaVenues.first(where: { $0.id == id })?.name
            ?? Defaults.cinemas.first(where: { $0.id == id })?.name
            ?? id
    }

    private static func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { store.set(data, forKey: key) }
    }

    private static func load<T: Decodable>(_ key: String) -> T? {
        guard let data = store.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
