import Foundation

/// Latest uploads from accounts a Mixcloud user follows, via Mixcloud's public API (no login needed).
///   GET https://api.mixcloud.com/<user>/following/
///   GET https://api.mixcloud.com/<followed>/cloudcasts/
///
/// FRAGILITY: low. Official, documented API. Mixcloud does rate-limit, so requests are throttled
/// and any account that fails is reported as a warning rather than failing the section.
enum MixcloudSource {
    private struct Page<T: Decodable>: Decodable {
        let data: [T]
        let paging: Paging?
    }
    private struct Paging: Decodable { let next: String? }
    private struct User: Decodable {
        let key: String
        let username: String
        let name: String?
    }
    private struct Cloudcast: Decodable {
        let key: String
        let url: String
        let name: String
        let created_time: String
        let audio_length: Int?
        let pictures: [String: String]?
        let user: User
    }

    static func fetch(username: String) async throws -> SourceResult<Mix> {
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        guard !user.isEmpty else {
            throw FetchError.notConfigured("Add your Mixcloud username in Settings to see new uploads from people you follow.")
        }

        var following: [User] = []
        var next = URL(string: "https://api.mixcloud.com/\(user)/following/?limit=100")
        var pages = 0
        while let url = next, pages < 6 {
            let page: Page<User>
            do {
                page = try JSONDecoder().decode(Page<User>.self, from: try await HTTP.data(from: url, accept: "application/json"))
            } catch FetchError.badStatus(404, _) {
                throw FetchError.notConfigured("Mixcloud user “\(username)” wasn't found. Check the username in Settings.")
            }
            following += page.data
            next = page.paging?.next.flatMap { URL(string: $0) }
            pages += 1
        }
        guard !following.isEmpty else {
            return SourceResult(items: [], warnings: ["You're not following anyone on Mixcloud yet."])
        }

        let lists = await boundedMap(following, limit: 5) { account -> [Mix]? in
            guard let url = URL(string: "https://api.mixcloud.com\(account.key)cloudcasts/?limit=5"),
                  let data = try? await HTTP.data(from: url, accept: "application/json"),
                  let page = try? JSONDecoder().decode(Page<Cloudcast>.self, from: data) else { return nil }
            return page.data.compactMap(mix(from:))
        }

        let failed = lists.filter { $0 == nil }.count
        if failed == following.count {
            throw FetchError.parse("Mixcloud didn't return any uploads — it may be rate-limiting. Try again in a few minutes.")
        }
        var seen = Set<String>()
        let mixes = lists.compactMap { $0 }.flatMap { $0 }
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.date > $1.date }
        let warnings = failed > 0 ? ["Couldn't load uploads from \(failed) of \(following.count) accounts."] : []
        return SourceResult(items: Array(mixes.prefix(200)), warnings: warnings)
    }

    private static let iso: ISO8601DateFormatter = ISO8601DateFormatter()
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func mix(from c: Cloudcast) -> Mix? {
        guard let url = URL(string: c.url),
              let date = iso.date(from: c.created_time) ?? isoFractional.date(from: c.created_time) else { return nil }
        let art = c.pictures?["extra_large"] ?? c.pictures?["large"] ?? c.pictures?["medium"]
        return Mix(id: c.key, title: c.name, uploader: c.user.name ?? c.user.username,
                   artworkURL: art.flatMap { URL(string: $0) }, date: date,
                   durationSeconds: c.audio_length, url: url)
    }
}
