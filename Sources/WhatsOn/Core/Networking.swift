import Foundation

/// Shared HTTP client. Every data source goes through here, so timeouts and headers live in one place.
enum HTTP {
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 180
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
            "Accept-Language": "en-GB,en;q=0.9"
        ]
        return URLSession(configuration: config)
    }()

    static func data(from url: URL, accept: String? = nil) async throws -> Data {
        var request = URLRequest(url: url)
        if let accept { request.setValue(accept, forHTTPHeaderField: "Accept") }
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw FetchError.badStatus(http.statusCode, url)
        }
        return data
    }

    static func text(from url: URL) async throws -> String {
        let data = try await data(from: url, accept: "text/html,application/xhtml+xml,*/*;q=0.8")
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }
}

/// Runs `transform` over `items` with at most `limit` in flight, keeping input order.
func boundedMap<T, R>(_ items: [T], limit: Int, _ transform: @escaping (T) async -> R) async -> [R] {
    guard !items.isEmpty else { return [] }
    var results = [R?](repeating: nil, count: items.count)
    await withTaskGroup(of: (Int, R).self) { group in
        var next = 0
        while next < min(limit, items.count) {
            let i = next
            group.addTask { (i, await transform(items[i])) }
            next += 1
        }
        while let finished = await group.next() {
            results[finished.0] = finished.1
            if next < items.count {
                let j = next
                group.addTask { (j, await transform(items[j])) }
                next += 1
            }
        }
    }
    return results.map { $0! }
}

/// Turns any error into a short sentence for the UI.
func describe(_ error: Error) -> String {
    if let urlError = error as? URLError {
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed: return "You're offline."
        case .timedOut: return "The request timed out."
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed: return "Couldn't reach the server."
        default: break
        }
    }
    if error is DecodingError { return "The data was in an unexpected format — the source may have changed." }
    return error.localizedDescription
}

// MARK: - HTML helpers (regex-based; good enough for meta tags and links)

enum HTML {
    static func firstMatch(_ pattern: String, in text: String,
                           options: NSRegularExpression.Options = [.caseInsensitive]) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return groups(m, ns)
    }

    static func allMatches(_ pattern: String, in text: String,
                           options: NSRegularExpression.Options = [.caseInsensitive]) -> [[String]] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { groups($0, ns) }
    }

    private static func groups(_ m: NSTextCheckingResult, _ ns: NSString) -> [String] {
        guard m.numberOfRanges > 1 else { return [] }
        return (1..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
    }

    static func replace(_ pattern: String, in text: String, with template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        return re.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: template)
    }

    /// Value of <meta property="key" content="..."> (or name="key"), either attribute order.
    static func meta(_ html: String, _ key: String) -> String? {
        let k = NSRegularExpression.escapedPattern(for: key)
        let patterns = [
            #"<meta\b[^>]*?(?:property|name)\s*=\s*["']"# + k + #"["'][^>]*?content\s*=\s*(?:"([^"]*)"|'([^']*)')"#,
            #"<meta\b[^>]*?content\s*=\s*(?:"([^"]*)"|'([^']*)')[^>]*?(?:property|name)\s*=\s*["']"# + k + #"["']"#
        ]
        for p in patterns {
            if let g = firstMatch(p, in: html), let value = g.first(where: { !$0.isEmpty }) {
                let decoded = decode(value).trimmingCharacters(in: .whitespacesAndNewlines)
                if !decoded.isEmpty { return decoded }
            }
        }
        return nil
    }

    static func title(_ html: String) -> String? {
        guard let g = firstMatch(#"<title[^>]*>([\s\S]*?)</title>"#, in: html) else { return nil }
        let t = decode(g[0]).trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// All href targets, resolved against `base`.
    static func links(in html: String, base: URL) -> [URL] {
        allMatches(#"href\s*=\s*["']([^"'#]+)["']"#, in: html).compactMap { g in
            URL(string: decode(g[0]).trimmingCharacters(in: .whitespaces), relativeTo: base)?.absoluteURL
        }
    }

    /// Visible-ish text: scripts/styles/tags removed, entities decoded, whitespace collapsed.
    static func plainText(_ html: String) -> String {
        var s = html
        for p in [#"<script\b[\s\S]*?</script>"#, #"<style\b[\s\S]*?</style>"#, #"<!--[\s\S]*?-->"#, #"<noscript\b[\s\S]*?</noscript>"#] {
            s = replace(p, in: s, with: " ")
        }
        s = replace(#"<[^>]+>"#, in: s, with: " ")
        s = decode(s)
        s = replace(#"\s+"#, in: s, with: " ")
        return s
    }

    static func decode(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var out = text
        // Numeric entities
        if let re = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);", options: .caseInsensitive) {
            let ns = out as NSString
            var result = ""
            var last = 0
            for m in re.matches(in: out, range: NSRange(location: 0, length: ns.length)) {
                result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
                let isHex = !ns.substring(with: m.range(at: 1)).isEmpty
                let digits = ns.substring(with: m.range(at: 2))
                if let v = UInt32(digits, radix: isHex ? 16 : 10), let scalar = Unicode.Scalar(v) {
                    result.append(Character(scalar))
                } else {
                    result += ns.substring(with: m.range)
                }
                last = m.range.location + m.range.length
            }
            result += ns.substring(from: last)
            out = result
        }
        let named: [(String, String)] = [
            ("&quot;", "\""), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " "),
            ("&ndash;", "–"), ("&mdash;", "—"), ("&rsquo;", "’"), ("&lsquo;", "‘"), ("&ldquo;", "“"),
            ("&rdquo;", "”"), ("&hellip;", "…"), ("&eacute;", "é"), ("&amp;", "&")
        ]
        for (k, v) in named { out = out.replacingOccurrences(of: k, with: v) }
        return out
    }
}

// MARK: - Date text parsing ("10 Sep 2026 – 22 Nov 2026", "13 March – 1 June 2026", "Until 4 Jan 2027")

enum DateText {
    private static let months = ["january", "february", "march", "april", "may", "june", "july",
                                 "august", "september", "october", "november", "december"]

    static func month(_ word: String) -> Int? {
        let w = word.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".,"))
        guard w.count >= 3 else { return nil }
        return months.firstIndex(where: { $0.hasPrefix(w) }).map { $0 + 1 }
    }

    static func date(day: Int, month: Int, year: Int) -> Date? {
        guard (1...31).contains(day), (1...12).contains(month), (1990...2100).contains(year) else { return nil }
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day; c.hour = 12
        return Calendar.london.date(from: c)
    }

    struct Span { let start: Date?; let end: Date? }

    private static let rangePattern =
        #"(?<!\d)(\d{1,2})(?:st|nd|rd|th)?(?:\s+([A-Za-z]{3,9})\.?)?(?:,?\s+(\d{4}))?\s*(?:–|—|-|to)\s*(?:[A-Za-z]{3,9},?\s+)?(\d{1,2})(?:st|nd|rd|th)?\s+([A-Za-z]{3,9})\.?,?\s+(\d{4})"#
    private static let untilPattern =
        #"(?:until|ends|closes|to)\s+(?:[A-Za-z]{3,9},?\s+)?(\d{1,2})(?:st|nd|rd|th)?\s+([A-Za-z]{3,9})\.?,?\s+(\d{4})"#

    /// First plausible date range in a block of text.
    static func span(in text: String) -> Span? {
        for g in HTML.allMatches(rangePattern, in: text) {
            guard let d2 = Int(g[3]), let m2 = month(g[4]), let y2 = Int(g[5]),
                  let end = date(day: d2, month: m2, year: y2),
                  let d1 = Int(g[0]) else { continue }
            var m1 = m2
            if !g[1].isEmpty {
                guard let m = month(g[1]) else { continue }
                m1 = m
            }
            var y1 = Int(g[2]) ?? y2
            if g[2].isEmpty, m1 > m2 { y1 = y2 - 1 }
            guard let start = date(day: d1, month: m1, year: y1), start <= end else { continue }
            return Span(start: start, end: end)
        }
        for g in HTML.allMatches(untilPattern, in: text) {
            if let d = Int(g[0]), let m = month(g[1]), let y = Int(g[2]), let end = date(day: d, month: m, year: y) {
                return Span(start: nil, end: end)
            }
        }
        return nil
    }
}
