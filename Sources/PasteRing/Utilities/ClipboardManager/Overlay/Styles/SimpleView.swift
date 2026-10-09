import SwiftUI

/// The default style: one fixed card showing what will be pasted. Cycling swaps the
/// content, nothing moves.
struct SimpleView: View {
    @ObservedObject var state: OverlayState
    @ObservedObject var settings: ClipboardSettings

    var body: some View {
        let item = state.selectedItem
        let height = settings.simpleHeight
        let fitted = EntryCard.fittedHeight(for: item, width: settings.simpleWidth, height: height)
        EntryCard(item: item, width: settings.simpleWidth, height: height)
            .modifier(OptionalClipActions(item: item))
            // Laid out at the usual height with the top pinned: a taller card for an image
            // grows downward only, and the position pill moves down with it.
            .frame(height: height, alignment: .top)
            .preference(key: OverlayGrowthKey.self, value: fitted - height)
            .transaction { $0.animation = nil }
    }
}

private struct OptionalClipActions: ViewModifier {
    let item: ClipItem?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let item {
            content.clipActions(item, trashInset: 22)
        } else {
            content
        }
    }
}
