import AppKit
import CryptoKit

/// The full clipboard contents of an entry: every pasteboard item with all its types.
typealias ClipPayload = [[String: Data]]

/// Saves entry contents and thumbnails as files next to the history, readable by this
/// user only, and removes them with their entry.
enum ClipPayloadStore {
    static let directory = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Estris", isDirectory: true)
        .appendingPathComponent("Clips", isDirectory: true)

    private static func payloadURL(_ id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).plist")
    }

    private static func thumbnailURL(_ id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString)-thumbnail.png")
    }

    static func save(_ payload: ClipPayload, thumbnail: Data?, for id: UUID) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try write(PropertyListEncoder().encode(payload), to: payloadURL(id))
            if let thumbnail {
                try write(thumbnail, to: thumbnailURL(id))
            }
        } catch {
            NSLog("Estris: failed to save clip contents: \(error)")
        }
    }

    static func load(_ id: UUID) -> ClipPayload? {
        guard let data = try? Data(contentsOf: payloadURL(id)) else { return nil }
        return try? PropertyListDecoder().decode(ClipPayload.self, from: data)
    }

    static func thumbnail(for id: UUID) -> NSImage? {
        NSImage(contentsOf: thumbnailURL(id))
    }

    static func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: payloadURL(id))
        try? FileManager.default.removeItem(at: thumbnailURL(id))
    }

    /// Removes files whose entry is gone, such as after a crash.
    static func deleteAll(except ids: Set<UUID>) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files {
            let id = file.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "-thumbnail", with: "")
            if let uuid = UUID(uuidString: id), !ids.contains(uuid) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    static func fingerprint(of payload: ClipPayload) -> String {
        var hasher = SHA256()
        for item in payload {
            for type in item.keys.sorted() {
                hasher.update(data: Data(type.utf8))
                hasher.update(data: item[type] ?? Data())
            }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

/// Thumbnails loaded once per entry.
@MainActor
enum ClipThumbnails {
    private static var cache: [UUID: NSImage] = [:]

    static func image(for item: ClipItem) -> NSImage? {
        guard item.kind == .image else { return nil }
        if let cached = cache[item.id] { return cached }
        let image = ClipPayloadStore.thumbnail(for: item.id)
        cache[item.id] = image
        return image
    }
}
