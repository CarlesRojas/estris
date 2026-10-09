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
        // No bounce, so the fade and slide read as one smooth motion.
        .animation(.spring(response: 0.45, dampingFraction: 1), value: state.position)
    }
}
