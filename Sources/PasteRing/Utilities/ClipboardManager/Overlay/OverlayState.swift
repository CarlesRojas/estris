import SwiftUI

@MainActor
final class OverlayState: ObservableObject {
    @Published var items: [ClipItem] = []
    /// Steps taken since opening. Unbounded so the ring keeps turning the same way when it wraps.
    @Published var position = 0
    /// Visible size of the screen the overlay opened on, for styles that scale to fit it.
    @Published var screenSize: CGSize?
    /// Grid tiles fitted to the screen the overlay opened on.
    @Published var gridLayout: GridLayout?

    var actions = OverlayActions()
    /// The shortcut that opened the overlay; its modifiers are held while it is open.
    @Published var activeShortcut = ClipboardSettings.defaultShortcut

    var selected: Int {
        items.isEmpty ? 0 : (position % items.count + items.count) % items.count
    }

    /// "2 of 12" for the position pill; nil when there is nothing to show.
    var positionText: String? {
        items.isEmpty ? nil : String(localized: "\(selected + 1) of \(items.count)")
    }

    var selectedItem: ClipItem? {
        items.indices.contains(selected) ? items[selected] : nil
    }

    struct Slot: Identifiable {
        let id: String
        let item: ClipItem
        let distance: Int
    }

    /// Places each entry at its circular distance from the selection, for styles that loop.
    /// `lap` is part of the identity, so an entry that wraps to the other end leaves and
    /// re-enters (with its transition) instead of sweeping across the selection.
    func circularSlots(within range: ClosedRange<Int>) -> [Slot] {
        let count = items.count
        guard count > 0 else { return [] }
        let lowest = -(count - 1) / 2
        return items.enumerated().compactMap { index, item in
            let raw = index - position
            let shifted = raw - lowest
            let lap = shifted >= 0 ? shifted / count : -((-shifted + count - 1) / count)
            let distance = raw - lap * count
            guard range.contains(distance) else { return nil }
            return Slot(id: "\(item.id)-\(lap)", item: item, distance: distance)
        }
    }
}
