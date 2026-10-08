import Foundation

struct ClipItem: Identifiable, Equatable {
    let id = UUID()
    let text: String
}

/// Most recent entry first.
@MainActor
final class ClipboardHistory {
    private(set) var items: [ClipItem] = []
    var limit = 50 {
        didSet { trim() }
    }

    func add(_ text: String) {
        items.removeAll { $0.text == text }
        items.insert(ClipItem(text: text), at: 0)
        trim()
    }

    func promote(_ item: ClipItem) {
        guard let index = items.firstIndex(of: item), index != 0 else { return }
        items.insert(items.remove(at: index), at: 0)
    }

    func clear() {
        items.removeAll()
    }

    private func trim() {
        if items.count > limit {
            items.removeLast(items.count - limit)
        }
    }
}
