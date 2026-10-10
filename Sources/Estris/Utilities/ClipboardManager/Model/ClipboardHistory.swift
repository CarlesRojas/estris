import Foundation

/// Most recent entry first. Saved to Application Support so it survives restarts.
@MainActor
final class ClipboardHistory: ObservableObject {
    @Published private(set) var items: [ClipItem] {
        didSet {
            deletePayloads(removedFrom: oldValue)
            save()
        }
    }

    var limit = 50 {
        didSet { trim() }
    }

    private static let fileURL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Estris", isDirectory: true)
        .appendingPathComponent("history.json")

    init() {
        items = Self.load()
        ClipPayloadStore.deleteAll(except: Set(items.map(\.id)))
    }

    /// Adds `item` as the most recent entry. With `removingDuplicates`, an older entry with
    /// the same content is dropped, so it moves to the top instead of appearing twice.
    func add(_ item: ClipItem, removingDuplicates: Bool) {
        var updated = items
        if removingDuplicates {
            updated.removeAll { $0.hasSameContent(as: item) }
        }
        updated.insert(item, at: 0)
        items = updated
        trim()
    }

    /// Drops entries copied before `date`.
    func removeEntries(olderThan date: Date) {
        guard items.contains(where: { $0.date < date }) else { return }
        items.removeAll { $0.date < date }
    }

    func promote(_ item: ClipItem) {
        guard let index = items.firstIndex(of: item), index != 0 else { return }
        var updated = items
        updated.insert(updated.remove(at: index), at: 0)
        items = updated
    }

    func remove(_ item: ClipItem) {
        items.removeAll { $0.id == item.id }
    }

    func clear() {
        items.removeAll()
    }

    private func trim() {
        if items.count > limit {
            items.removeLast(items.count - limit)
        }
    }

    private func deletePayloads(removedFrom oldItems: [ClipItem]) {
        let kept = Set(items.map(\.id))
        for item in oldItems where item.hasPayload == true && !kept.contains(item.id) {
            ClipPayloadStore.delete(item.id)
        }
    }

    private static func load() -> [ClipItem] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([ClipItem].self, from: data)) ?? []
    }

    private func save() {
        let url = Self.fileURL
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(items).write(to: url, options: .atomic)
            // Clipboard contents can be sensitive: readable by this user only.
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            NSLog("Estris: failed to save history: \(error)")
        }
    }
}
