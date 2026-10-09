import SwiftUI

/// Cover Flow style: the selected card faces you, the others tilt away on either side.
struct CarouselView: View {
    private static let visibleRange = 3

    @ObservedObject var state: OverlayState
    @ObservedObject var settings: ClipboardSettings

    private var frontGrowth: CGFloat {
        ContentCard.fittedHeight(for: state.selectedItem, width: width, height: height) - height
    }

    private var width: CGFloat { settings.carouselWidth }
    private var height: CGFloat { settings.carouselHeight }

    var body: some View {
        ZStack {
            if state.items.isEmpty {
                ContentCard(item: nil, isSelected: true, width: width, height: height)
            } else {
                ForEach(Array(state.items.enumerated()), id: \.element.id) { index, item in
                    let distance = index - state.selected
                    if abs(distance) <= Self.visibleRange {
                        // No line limit: the text fills whatever height the card has.
                        ContentCard(item: item, isSelected: distance == 0, width: width, height: height, lineLimit: nil, growsToFitImage: true)
                            .clipActions(item, trashInset: 16)
                            // Same layout height for every card, top pinned: a card holding an
                            // image grows downward only.
                            .frame(height: height, alignment: .top)
                            .rotation3DEffect(
                                .degrees(distance == 0 ? 0 : (distance < 0 ? 45 : -45)),
                                axis: (x: 0, y: 1, z: 0),
                                perspective: 0.6
                            )
                            .scaleEffect(distance == 0 ? 1 : 0.82)
                            .offset(x: offset(distance))
                            .zIndex(Double(-abs(distance)))
                    }
                }
            }
        }
        .frame(width: width * 3.5, height: height + 80)
        // Just below the front card, moving down when it grows for an image.
        .overlay {
            if let position = state.positionText {
                PositionPill(text: position)
                    .offset(y: height / 2 + max(0, frontGrowth) + 30)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: state.selected)
    }

    private func offset(_ distance: Int) -> CGFloat {
        guard distance != 0 else { return 0 }
        // Proportional to the card width, so neighbours overlap the same way at any size.
        let magnitude = width * 0.73 + CGFloat(abs(distance) - 1) * width * 0.31
        return distance < 0 ? -magnitude : magnitude
    }
}
