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
        GalleryConfig(name: "Lisson Gallery Cork Street", url: "https://www.artrabbit.com/organisations/lisson-gallery-22-cork-street")
    ]

    /// Defaults from the first release. Anything in `galleries` not listed here is "new" and gets
    /// added to existing installs once (and stays removed if you delete it).
    static let firstReleaseGalleryURLs: Set<String> = Set(galleries.prefix(13).map(\.url))

    /// The West End page every private-gallery show comes from (one request for all of them).
    static let westEndURL = URL(string: "https://www.galleriesnow.net/exhibitions/london-west-end")!

    /// Galleries on that page as of Nov 2026, with postcode districts. Refreshed from the page on every load.
    static let westEndCatalogue: [WestEndGallery] = {
        let raw: [(String, String)] = [
        ("Ab-Anbar", "W1W"), ("Albion Jeune", "W1W"), ("Alison Jacques", "W1S"), ("Alon Zakaim Fine Art", "W1S"),
        ("Ames Yavuz", "W1K"), ("Annely Juda Fine Art", "W1S"), ("Belmacz", "W1K"), ("Bluerider ART London", "W1S"),
        ("Colnaghi", "SW1Y"), ("Cristea Roberts Gallery", "SW1Y"), ("DES BAINS", "W1W"), ("David Gill", "SW1Y"),
        ("David Zwirner", "W1S"), ("Dirimart London", "W1B"), ("Frith Street Gallery", "W1F"), ("GRIMM", "SW1Y"),
        ("Galerie Max Hetzler", "W1S"), ("Gazelli Art House", "W1S"), ("General Assembly", "W1S"), ("Goodman Gallery", "W1S"),
        ("Grosvenor Gallery", "SW1Y"), ("Hanina Fine Arts", "W1C"), ("Hauser & Wirth", "W1S"), ("Hazlitt Holland-Hibbert", "SW1Y"),
        ("Helly Nahmad Gallery | Nahmad Projects", "W1S"), ("LAMB", "W1S"), ("Luxembourg + Co.", "W1S"), ("No.9 Cork Street", "W1S"),
        ("Opera Gallery", "W1S"), ("Ordovas", "W1S"), ("Pace", "W1S"), ("Perrotin London", "W1K"),
        ("Pilar Corrias, Conduit Street", "W1S"), ("Pilar Corrias, Savile Row", "W1S"), ("Pippy Houldsworth Gallery", "W1B"),
        ("Pontone Gallery", "W1T"), ("Robilant", "W1S"), ("Ronchini", "W1S"), ("SETAREH", "W1K"), ("Saatchi Yates", "SW1Y"),
        ("Shapero Modern", "W1S"), ("Sprovieri", "W1B"), ("Sprüth Magers", "W1S"), ("Sylvia Kouvali", "W1K"),
        ("THE TAGLI", "W1W"), ("Tache", "W1T"), ("Thaddaeus Ropac", "W1S"), ("The Mayor Gallery", "SW1Y"),
        ("Thomas Dane Gallery", "SW1Y"), ("Timothy Taylor", "W1J"), ("Upsilon Gallery", "W1K"), ("Vardaxoglou Gallery", "W1D"),
        ("Waddington Custot", "W1S"), ("rosenfeld", "W1K"), ("sketch", "W1S")
        ]
        return raw.map { WestEndGallery(name: $0.0, postcode: $0.1) }
    }()

    /// Contemporary galleries within a few minutes' walk of Grafton Street — ticked by default.
    static let westEndSelected: [String] = [
        "David Zwirner", "Sprüth Magers", "Hauser & Wirth", "Pace", "Thaddaeus Ropac", "Galerie Max Hetzler",
        "Thomas Dane Gallery", "Pilar Corrias, Conduit Street", "Pilar Corrias, Savile Row", "Alison Jacques",
        "Timothy Taylor", "Goodman Gallery", "Perrotin London", "LAMB", "GRIMM", "Sylvia Kouvali", "No.9 Cork Street",
        "Waddington Custot", "Ordovas", "Gazelli Art House", "Sprovieri", "Pippy Houldsworth Gallery", "Luxembourg + Co.",
        "Annely Juda Fine Art", "Dirimart London", "Saatchi Yates", "Ronchini", "Cristea Roberts Gallery"
    ]

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
    @Published var westEndSelected: [String] { didSet { Self.store.set(westEndSelected, forKey: "westEndSelected") } }
    @Published var westEndCatalogue: [WestEndGallery] { didSet { Self.save(westEndCatalogue, "westEndCatalogue") } }
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
        westEndSelected = d.stringArray(forKey: "westEndSelected") ?? Defaults.westEndSelected
        westEndCatalogue = Self.load("westEndCatalogue") ?? Defaults.westEndCatalogue

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
        // The previous version added one combined "Mayfair & St James's" entry; the West End checklist replaces it.
        list.removeAll { $0.kind == .galleriesNow && $0.filter == "W1S, W1J, W1K, W1B, SW1Y" }
        let existing = Set(list.map(\.url))
        for g in Defaults.galleries where !offered.contains(g.url) && !existing.contains(g.url) {
            list.append(g)
        }
        galleries = list
        Self.save(list, "galleries")
        d.set(Array(offered.union(Defaults.galleries.map(\.url))), forKey: "offeredDefaultGalleryURLs")
    }

    /// Keep galleries seen before (so ticked ones don't vanish if a gallery has a quiet week), add new ones.
    func mergeWestEndCatalogue(_ fresh: [WestEndGallery]) {
        var byName = Dictionary(westEndCatalogue.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        for g in fresh { byName[g.name] = g }
        let merged = byName.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if merged != westEndCatalogue { westEndCatalogue = merged }
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
