import SwiftUI

/// A deck of cards: upcoming entries peek out behind the selected one, and moving on
/// slides the top card away and sends it to the back.
struct DeckView: View {
    private static let peek: CGFloat = 18
    private static let depth = 4

    @ObservedObject var state: OverlayState

    var body: some View {
        ZStack {
            if state.items.isEmpty {
                ContentCard(item: nil, isSelected: true, width: 480, height: 200)
            } else {
                // Distance -1 is the card just dealt; it stays rendered so it can slide out.
                ForEach(state.circularSlots(within: -1...Self.depth)) { slot in
                    let distance = slot.distance
                    ContentCard(item: slot.item, isSelected: distance == 0, width: 480, height: 200, lineLimit: 6)
                        .scaleEffect(distance <= 0 ? 1 : 1 - CGFloat(distance) * 0.05)
                        .offset(y: distance < 0 ? 240 : -CGFloat(distance) * Self.peek)
                        .opacity(distance < 0 ? 0 : 1 - Double(distance) * 0.18)
                        .zIndex(Double(-distance))
                        .transition(.opacity)
                }
            }
        }
        .frame(width: 640, height: 420)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: state.position)
    }
}
