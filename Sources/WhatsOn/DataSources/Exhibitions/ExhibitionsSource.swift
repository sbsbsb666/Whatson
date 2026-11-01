import Foundation

/// Exhibitions section: fans out to one scraper per gallery and merges the results.
/// One gallery failing only adds a warning; the section fails only if every gallery fails.
enum ExhibitionsSource {
    struct Output {
        var result: SourceResult<Exhibition>
        /// Every gallery on the West End page, for the Settings checklist (nil if that page didn't load).
        var westEndCatalogue: [WestEndGallery]?
    }

    static func fetch(galleries: [GalleryConfig], westEnd: [String]) async throws -> Output {
        let enabled = galleries.filter { $0.enabled && !$0.url.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !enabled.isEmpty || !westEnd.isEmpty else {
            throw FetchError.notConfigured("Pick some galleries in Settings to see exhibitions.")
        }

        // The West End page (one request covers every Mayfair / St James's gallery) runs alongside the others.
        async let westEndFetch = westEndResult(selected: westEnd)

        let results = await boundedMap(enabled, limit: 4) { gallery -> Result<[Exhibition], Error> in
            do { return .success(try await fetchGallery(gallery)) }
            catch { return .failure(error) }
        }

        var items: [Exhibition] = []
        var warnings: [String] = []
        var sourcesTried = enabled.count
        var sourcesFailed = 0
        for (gallery, result) in zip(enabled, results) {
            switch result {
            case .success(let found): items += found
            case .failure(let error):
                warnings.append("\(gallery.name): \(describe(error))")
                sourcesFailed += 1
            }
        }

        var catalogue: [WestEndGallery]?
        switch await westEndFetch {
        case .success(let west):
            catalogue = west.catalogue
            if !westEnd.isEmpty { items += west.items }
        case .failure(let error):
            if !westEnd.isEmpty {
                warnings.append("West End galleries (GalleriesNow): \(describe(error))")
                sourcesFailed += 1
            }
        }
        if !westEnd.isEmpty { sourcesTried += 1 }

        if items.isEmpty && sourcesFailed == sourcesTried {
            throw FetchError.parse("None of your galleries could be loaded.")
        }

        let cal = Calendar.london
        let today = cal.startOfDay(for: Date())
        let horizon = cal.date(byAdding: .day, value: 120, to: today)!
        var seen = Set<String>()
        let filtered = items.filter { item in
            guard seen.insert(item.id).inserted else { return false }
            if let end = item.endDate, end < today { return false }
            if let start = item.startDate, start > horizon { return false }
            return true
        }
        return Output(result: SourceResult(items: filtered, warnings: warnings), westEndCatalogue: catalogue)
    }

    private static func westEndResult(selected: [String]) async -> Result<(items: [Exhibition], catalogue: [WestEndGallery]), Error> {
        do { return .success(try await GalleriesNowSource.fetchWestEnd(selected: selected)) }
        catch { return .failure(error) }
    }

    static func fetchGallery(_ gallery: GalleryConfig) async throws -> [Exhibition] {
        guard let url = URL(string: gallery.url.trimmingCharacters(in: .whitespaces)), url.scheme?.hasPrefix("http") == true else {
            throw FetchError.parse("That page address isn't valid.")
        }
        switch gallery.kind {
        case .artRabbit:
            return try await ArtRabbitSource.fetch(organisation: url, venue: gallery.name)
        case .galleriesNow:
            return try await GalleriesNowSource.fetch(listing: url, filter: gallery.filter, fallbackVenue: gallery.name)
        case .website:
            return try await GenericGallerySource.fetch(listing: url, linkPrefix: gallery.linkPrefix, venue: gallery.name)
        }
    }
}
