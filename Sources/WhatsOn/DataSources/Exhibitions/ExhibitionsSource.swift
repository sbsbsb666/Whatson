import Foundation

/// Exhibitions section: fans out to one scraper per gallery and merges the results.
/// One gallery failing only adds a warning; the section fails only if every gallery fails.
enum ExhibitionsSource {
    static func fetch(galleries: [GalleryConfig]) async throws -> SourceResult<Exhibition> {
        let enabled = galleries.filter { $0.enabled && !$0.url.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !enabled.isEmpty else {
            throw FetchError.notConfigured("Add some galleries in Settings to see exhibitions.")
        }

        let results = await boundedMap(enabled, limit: 4) { gallery -> Result<[Exhibition], Error> in
            do { return .success(try await fetchGallery(gallery)) }
            catch { return .failure(error) }
        }

        var items: [Exhibition] = []
        var warnings: [String] = []
        for (gallery, result) in zip(enabled, results) {
            switch result {
            case .success(let found): items += found
            case .failure(let error): warnings.append("\(gallery.name): \(describe(error))")
            }
        }
        if items.isEmpty && warnings.count == enabled.count {
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
        return SourceResult(items: filtered, warnings: warnings)
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
