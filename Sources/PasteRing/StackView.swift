import SwiftUI

/// A pile of cards: the selected one in front, the next few peeking out above it, each
/// smaller and showing less the further back it is. Moving on drops the front card down
/// behind the pile while the next one comes forward.
struct StackView: View {
    private static let cardWidth: CGFloat = 520
    private static let cardHeight: CGFloat = 170
    /// How far each card's top sits above the front card's top. Gaps shrink with depth.
    private static let peeks: [CGFloat] = [0, 24, 42, 55, 63]
    private static let scales: [CGFloat] = [1, 0.94, 0.89, 0.85, 0.82]

    @ObservedObject var state: OverlayState

    var body: some View {
        ZStack {
            if state.items.isEmpty {
                EntryCard(item: nil, width: Self.cardWidth, height: Self.cardHeight)
            } else {
                // Distance -1 is the card that just left the front; it stays rendered so it
                // can slide down out of sight behind the new front card.
                ForEach(state.circularSlots(within: -1...(Self.peeks.count - 1))) { slot in
                    let distance = slot.distance
                    EntryCard(item: slot.item, width: Self.cardWidth, height: Self.cardHeight, isSelected: distance == 0)
                        .clipActions(slot.item, trashInset: 22)
                        .allowsHitTesting(distance >= 0)
                        .scaleEffect(distance < 0 ? 0.9 : Self.scales[distance], anchor: .top)
                        .offset(y: distance < 0 ? Self.cardHeight * 0.9 : -Self.peeks[distance])
                        .opacity(distance < 0 ? 0 : 1)
                        // The leaving card drops straight to the back, so it passes behind the pile.
                        .zIndex(distance < 0 ? -100 : Double(-distance))
                        .transition(.opacity)
                }
            }
        }
        .frame(width: 640, height: 420)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: state.position)
    }
}

extension String {
    /// Trimmed, with line breaks shown as ⏎ so one-line previews stay meaningful.
    var singleLine: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ⏎ ")
    }
}
