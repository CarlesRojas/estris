import SwiftUI

/// The default style: one fixed card showing what will be pasted. Cycling swaps the
/// content, nothing moves.
struct SimpleView: View {
    @ObservedObject var state: OverlayState
    @ObservedObject var settings: ClipboardSettings

    var body: some View {
        let item = state.selectedItem
        EntryCard(item: item, width: settings.simpleWidth, height: settings.simpleHeight)
            .modifier(OptionalClipActions(item: item))
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
