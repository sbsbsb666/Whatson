import Foundation
import AppKit
import CryptoKit

/// Last good results per section, stored as JSON so the app opens instantly and works offline.
enum Cache {
    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("WhatsOnLondon", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let imageDirectory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("WhatsOnLondon/Images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static func file(_ key: String) -> URL { directory.appendingPathComponent("\(key).json") }

    static func load<T: Codable>(_ key: String) -> Snapshot<T>? {
        guard let data = try? Data(contentsOf: file(key)) else { return nil }
        return try? JSONDecoder().decode(Snapshot<T>.self, from: data)
    }

    static func save<T: Codable>(_ snapshot: Snapshot<T>, key: String) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: file(key), options: .atomic)
    }

    static func clearAll() {
        let fm = FileManager.default
        for dir in [directory, imageDirectory] {
            for f in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] {
                try? fm.removeItem(at: f)
            }
        }
    }

    /// Drop cached images nobody has looked at for a while.
    static func pruneImages(olderThanDays days: Int = 45) {
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        let files = (try? fm.contentsOfDirectory(at: imageDirectory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for f in files {
            let modified = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if modified < cutoff { try? fm.removeItem(at: f) }
        }
    }
}

/// Memory + disk image cache so artwork shows instantly and offline.
actor ImageLoader {
    static let shared = ImageLoader()

    private let memory = NSCache<NSURL, NSImage>()
    private var inFlight: [URL: Task<NSImage?, Never>] = [:]

    init() { memory.countLimit = 400 }

    func image(for url: URL) async -> NSImage? {
        if let cached = memory.object(forKey: url as NSURL) { return cached }
        if let running = inFlight[url] { return await running.value }

        let digest = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        let file = Cache.imageDirectory.appendingPathComponent(digest)

        let task = Task<NSImage?, Never> {
            if let data = try? Data(contentsOf: file), let img = NSImage(data: data) { return img }
            guard let data = try? await HTTP.data(from: url, accept: "image/*"),
                  let img = NSImage(data: data) else { return nil }
            try? data.write(to: file, options: .atomic)
            return img
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image { memory.setObject(image, forKey: url as NSURL) }
        return image
    }
}
