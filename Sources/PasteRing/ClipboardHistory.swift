import Foundation

struct ClipItem: Identifiable, Equatable {
    let id = UUID()
    let text: String
}

/// Most recent entry first.
@MainActor
final class ClipboardHistory {
    private(set) var items: [ClipItem] = []
    let limit = 50

    func add(_ text: String) {
        items.removeAll { $0.text == text }
        items.insert(ClipItem(text: text), at: 0)
        if items.count > limit {
            items.removeLast(items.count - limit)
        }
    }

    func promote(_ item: ClipItem) {
        guard let index = items.firstIndex(of: item), index != 0 else { return }
        items.insert(items.remove(at: index), at: 0)
    }

    func clear() {
        items.removeAll()
    }
}
