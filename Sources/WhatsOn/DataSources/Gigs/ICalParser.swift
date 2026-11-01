import Foundation

struct ICalEvent {
    var uid = ""
    var summary = ""
    var location = ""
    var description = ""
    var url: String?
    var start: Date?
    var allDay = false
}

/// Minimal RFC 5545 reader: VEVENT blocks, line unfolding, escapes, DTSTART in UTC / TZID / all-day.
enum ICalParser {
    static func parse(_ text: String) -> [ICalEvent] {
        let normalised = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var lines: [String] = []
        for raw in normalised.split(separator: "\n", omittingEmptySubsequences: false) {
            if (raw.hasPrefix(" ") || raw.hasPrefix("\t")), !lines.isEmpty {
                lines[lines.count - 1] += raw.dropFirst()
            } else {
                lines.append(String(raw))
            }
        }

        var events: [ICalEvent] = []
        var current: ICalEvent?
        for line in lines {
            if line == "BEGIN:VEVENT" { current = ICalEvent(); continue }
            if line == "END:VEVENT" {
                if let c = current { events.append(c) }
                current = nil
                continue
            }
            guard current != nil, let colon = line.firstIndex(of: ":") else { continue }
            let head = line[..<colon]
            let value = String(line[line.index(after: colon)...])
            let parts = head.split(separator: ";")
            guard let nameSub = parts.first else { continue }
            let name = nameSub.uppercased()
            var params: [String: String] = [:]
            for p in parts.dropFirst() {
                let kv = p.split(separator: "=", maxSplits: 1)
                if kv.count == 2 {
                    params[kv[0].uppercased()] = kv[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                }
            }
            switch name {
            case "UID": current?.uid = value
            case "SUMMARY": current?.summary = unescape(value)
            case "LOCATION": current?.location = unescape(value)
            case "DESCRIPTION": current?.description = unescape(value)
            case "URL": current?.url = value
            case "DTSTART":
                if let parsed = parseDate(value, tzid: params["TZID"], valueType: params["VALUE"]) {
                    current?.start = parsed.0
                    current?.allDay = parsed.1
                }
            default: break
            }
        }
        return events
    }

    static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    static func parseDate(_ value: String, tzid: String?, valueType: String?) -> (Date, Bool)? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        let v = value.trimmingCharacters(in: .whitespaces)
        if valueType == "DATE" || v.count == 8 {
            f.dateFormat = "yyyyMMdd"
            f.timeZone = .london
            return f.date(from: v).map { ($0, true) }
        }
        if v.hasSuffix("Z") {
            f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            f.timeZone = TimeZone(identifier: "UTC")
        } else {
            f.dateFormat = "yyyyMMdd'T'HHmmss"
            f.timeZone = tzid.flatMap { TimeZone(identifier: $0) } ?? .london
        }
        return f.date(from: v).map { ($0, false) }
    }
}
