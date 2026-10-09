import Foundation

/// The last things Auto Quit noticed and decided, shown in its settings so it's easy to
/// see why an app was or wasn't quit. Also written to the system log.
@MainActor
final class AutoQuitActivity: ObservableObject {
    struct Entry: Identifiable {
        let id = UUID()
        let date: Date
        let message: String
    }

    private static let limit = 30

    @Published private(set) var entries: [Entry] = []

    func record(_ message: String) {
        NSLog("PasteRing Auto Quit: %@", message)
        entries.insert(Entry(date: Date(), message: message), at: 0)
        if entries.count > Self.limit {
            entries.removeLast(entries.count - Self.limit)
        }
    }

    func clear() {
        entries.removeAll()
    }
}
