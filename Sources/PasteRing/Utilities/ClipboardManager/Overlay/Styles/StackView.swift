import SwiftUI

/// A pile of cards: the selected one in front, the next few peeking out above it, each
/// smaller and showing less the further back it is. Moving on slides the front card down
/// and fades it out while the next one comes forward; moving back plays it in reverse,
/// the previous card rising from below as it fades in.
struct StackView: View {
    /// How far each card's top sits above the front card's top. Gaps shrink with depth.
    private static let peeks: [CGFloat] = [0, 24, 42, 55, 63]
    private static let scales: [CGFloat] = [1, 0.94, 0.89, 0.85, 0.82]

    @ObservedObject var state: OverlayState
    @ObservedObject var settings: ClipboardSettings

    private var frontGrowth: CGFloat {
        EntryCard.fittedHeight(for: state.selectedItem, width: width, height: height) - height
    }

    /// How much of a card, from its top and before scaling, is drawn. Cards behind show the
    /// strip above the front card plus a little under its rounded corners.
    private func visibleHeight(_ distance: Int) -> CGFloat {
        guard distance > 0 else { return 100_000 }
        return Self.peeks[distance] / Self.scales[distance] + 24
    }

    private var width: CGFloat { settings.stackWidth }
    private var height: CGFloat { settings.stackHeight }

    var body: some View {
        ZStack {
            if state.items.isEmpty {
                EntryCard(item: nil, width: width, height: height)
            } else {
                // Distance -1 is the card just below the front, invisible: the one that just
                // left going forward, and the one that rises in going back.
                ForEach(state.circularSlots(within: -1...(Self.peeks.count - 1))) { slot in
                    let distance = slot.distance
                    EntryCard(item: slot.item, width: width, height: height, isSelected: distance == 0)
                        .clipActions(slot.item, trashInset: 22)
                        // Same layout height for every card, top pinned: a card holding an image
                        // grows downward only.
                        .frame(height: height, alignment: .top)
                        // Cards behind only show their top strip: the rest would show through
                        // the translucent front card, or below it when they are taller.
                        .mask(alignment: .top) {
                            Rectangle().frame(height: visibleHeight(distance))
                        }
                        .allowsHitTesting(distance >= 0)
                        .scaleEffect(distance < 0 ? 0.97 : Self.scales[distance], anchor: .top)
                        .offset(y: distance < 0 ? height * 0.45 : -Self.peeks[distance])
                        .opacity(distance < 0 ? 0 : 1)
                        // The leaving card stays on top while it slides down and fades.
                        .zIndex(distance < 0 ? 1 : Double(-distance))
                        .transition(.opacity)
                }
            }
        }
        .frame(width: width + 120, height: height + 250)
        // Just below the front card, moving down when it grows for an image.
        .overlay {
            if let position = state.positionText {
                PositionPill(text: position)
                    .offset(y: height / 2 + max(0, frontGrowth) + 30)
            }
        }
        // No bounce, so the fade and slide read as one smooth motion.
        .animation(.spring(response: 0.45, dampingFraction: 1), value: state.position)
    }
}
