import Foundation

// MARK: - London time

extension TimeZone {
    static let london = TimeZone(identifier: "Europe/London")!
}

extension Calendar {
    static let london: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .london
        cal.locale = Locale(identifier: "en_GB")
        return cal
    }()

    func daysBetween(_ from: Date, _ to: Date) -> Int {
        dateComponents([.day], from: startOfDay(for: from), to: startOfDay(for: to)).day ?? 0
    }
}

enum Fmt {
    private static func make(_ template: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.timeZone = .london
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }
    static let dayMonth = make("d MMM")
    static let dayMonthYear = make("d MMM yyyy")
    static let longDate = make("EEEE d MMMM")
    static let weekdayShort = make("EEE")
    static let weekdayLong = make("EEEE")
    static let dayNumber = make("d")
    static let monthYear = make("MMMM yyyy")
    static let time = make("HH:mm")

    /// "Today", "Tomorrow", "Thursday", or "Thu 14 Nov"
    static func relativeDay(_ date: Date, now: Date = Date()) -> String {
        let days = Calendar.london.daysBetween(now, date)
        switch days {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case 2...6: return weekdayLong.string(from: date)
        default: return "\(weekdayShort.string(from: date)) \(dayMonth.string(from: date))"
        }
    }

    static func duration(_ seconds: Int?) -> String? {
        guard let s = seconds, s > 0 else { return nil }
        let h = s / 3600, m = (s % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m) min"
    }
}

// MARK: - Items

struct Exhibition: Codable, Hashable, Identifiable {
    let id: String
    let title: String
    let venue: String
    let startDate: Date?
    let endDate: Date?
    let imageURL: URL?
    let url: URL

    private var today: Date { Calendar.london.startOfDay(for: Date()) }

    var isOpeningSoon: Bool {
        guard let s = startDate else { return false }
        return Calendar.london.startOfDay(for: s) > today
    }

    var daysUntilClose: Int? {
        endDate.map { Calendar.london.daysBetween(Date(), $0) }
    }

    var daysSinceOpen: Int? {
        startDate.map { Calendar.london.daysBetween($0, Date()) }
    }

    var dateLabel: String {
        if isOpeningSoon, let s = startDate { return "Opens \(Fmt.dayMonth.string(from: s))" }
        guard let e = endDate else { return "" }
        let sameYear = Calendar.london.component(.year, from: e) == Calendar.london.component(.year, from: Date())
        return "Until \((sameYear ? Fmt.dayMonth : Fmt.dayMonthYear).string(from: e))"
    }

    var badge: String? {
        if let d = daysUntilClose, !isOpeningSoon, d <= 10 { return d <= 0 ? "Last day" : "Closing soon" }
        if let d = daysSinceOpen, d >= 0, d <= 7 { return "Just opened" }
        if isOpeningSoon, let s = startDate, Calendar.london.daysBetween(Date(), s) <= 7 { return "Opens soon" }
        return nil
    }
}

struct Gig: Codable, Hashable, Identifiable {
    let id: String
    let artist: String
    let venue: String
    let location: String
    let date: Date
    let allDay: Bool
    let url: URL?

    var timeLabel: String {
        allDay ? Fmt.relativeDay(date) : "\(Fmt.relativeDay(date)), \(Fmt.time.string(from: date))"
    }
}

struct Mix: Codable, Hashable, Identifiable {
    let id: String
    let title: String
    let uploader: String
    let artworkURL: URL?
    let date: Date
    let durationSeconds: Int?
    let url: URL
}

struct SubstackPost: Codable, Hashable, Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let publication: String
    let author: String?
    let date: Date
    let url: URL
    let imageURL: URL?
    let logoURL: URL?
    let isPaid: Bool
    /// "newsletter", "podcast", "video", "thread" …
    let kind: String?

    var kindSymbol: String? {
        switch kind {
        case "podcast": return "headphones"
        case "video": return "play.rectangle"
        case "thread": return "bubble.left.and.bubble.right"
        default: return nil
        }
    }
}

struct Showtime: Codable, Hashable, Identifiable {
    let id: String
    let time: Date
    let bookingURL: URL?
    let soldOut: Bool
    let screen: String?
}

struct Film: Codable, Hashable, Identifiable {
    let id: String
    let title: String
    let year: String?
    let runtimeMinutes: Int?
    let posterURL: URL?
    let url: URL?
    var showtimes: [Showtime]

    var meta: String? {
        let parts = [year, runtimeMinutes.map { "\($0) min" }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

struct CinemaVenue: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    var films: [Film]
}

/// A private gallery listed on GalleriesNow's West End page.
struct WestEndGallery: Codable, Hashable, Identifiable {
    var id: String { name }
    let name: String
    /// Postcode district, e.g. "W1S".
    let postcode: String

    var area: String {
        switch postcode {
        case "W1S", "W1J", "W1K": return "Mayfair"
        case "SW1Y", "SW1A": return "St James’s"
        case "W1B": return "Regent Street"
        case "W1F", "W1D": return "Soho"
        case "W1W", "W1T": return "Fitzrovia"
        case "W1C", "W1U", "W1H", "W1G": return "Marylebone"
        default: return postcode
        }
    }
}

struct CinemaVenueRef: Codable, Hashable, Identifiable {
    let id: String
    let name: String
}

struct GalleryConfig: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var url: String
    /// Generic gallery pages only: the path that exhibition links start with.
    var linkPrefix: String = ""
    var enabled: Bool = true
    /// GalleriesNow pages only: comma-separated postcode districts or names to keep.
    var filter: String = ""

    enum Kind { case artRabbit, galleriesNow, website }

    var kind: Kind {
        let u = url.lowercased()
        if u.contains("artrabbit.com") { return .artRabbit }
        if u.contains("galleriesnow.net") { return .galleriesNow }
        return .website
    }

    init(id: UUID = UUID(), name: String, url: String, linkPrefix: String = "", enabled: Bool = true, filter: String = "") {
        self.id = id
        self.name = name
        self.url = url
        self.linkPrefix = linkPrefix
        self.enabled = enabled
        self.filter = filter
    }

    // Tolerant decoding, so settings saved by older versions keep working when fields are added.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        linkPrefix = try c.decodeIfPresent(String.self, forKey: .linkPrefix) ?? ""
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        filter = try c.decodeIfPresent(String.self, forKey: .filter) ?? ""
    }
}

// MARK: - Section plumbing

/// What a data source returns. `warnings` are partial failures (e.g. one gallery didn't load).
struct SourceResult<T> {
    var items: [T]
    var warnings: [String] = []
}

/// What the UI renders for one section: last good items plus status.
struct SectionState<T: Codable> {
    var items: [T] = []
    var fetchedAt: Date?
    var warnings: [String] = []
    var isLoading = false
    var error: String?
    var setupMessage: String?

    init() {}

    init(snapshot: Snapshot<T>?) {
        if let s = snapshot {
            items = s.items
            fetchedAt = s.fetchedAt
            warnings = s.warnings
        }
    }
}

struct Snapshot<T: Codable>: Codable {
    var items: [T]
    var fetchedAt: Date
    var warnings: [String]
}

enum FetchError: LocalizedError {
    case badStatus(Int, URL)
    case notConfigured(String)
    case parse(String)

    var errorDescription: String? {
        switch self {
        case .badStatus(let code, let url): return "\(url.host ?? "The server") returned an error (HTTP \(code))."
        case .notConfigured(let message): return message
        case .parse(let message): return message
        }
    }
}
