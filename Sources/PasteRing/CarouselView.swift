import SwiftUI

/// Cover Flow style: the selected card faces you, the others tilt away on either side.
struct CarouselView: View {
    private static let visibleRange = 3

    @ObservedObject var state: OverlayState
    @ObservedObject var settings: ClipboardSettings

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
                        ContentCard(item: item, isSelected: distance == 0, width: width, height: height, lineLimit: nil)
                            .clipActions(item, trashInset: 16)
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
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: state.selected)
    }

    private func offset(_ distance: Int) -> CGFloat {
        guard distance != 0 else { return 0 }
        // Proportional to the card width, so neighbours overlap the same way at any size.
        let magnitude = width * 0.73 + CGFloat(abs(distance) - 1) * width * 0.31
        return distance < 0 ? -magnitude : magnitude
    }
}

/// Fixed-size card with the source app and the text, shared by Carousel and Grid.
struct ContentCard: View {
    /// Width kept free in the header for the date and trash button.
    static let cornerReserve: CGFloat = 120

    let item: ClipItem?
    let isSelected: Bool
    @Environment(\.overlayActions) private var actions
    var width: CGFloat = 260
    var height: CGFloat = 260
    var lineLimit: Int? = 9

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let item {
                HStack(spacing: 8) {
                    AppIconView(bundleID: item.sourceBundleID, size: 24)
                    Text(AppIcons.name(for: item.sourceBundleID) ?? "Unknown app")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                // Room for the date and trash button in the corner.
                .padding(.trailing, actions.isEnabled ? Self.cornerReserve : 0)
                // Same font whether selected or not: a heavier weight rewraps the text.
                Text(item.text.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.body)
                    .lineLimit(lineLimit)
                    .truncationMode(.tail)
            } else {
                Text("Clipboard history is empty")
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: width, height: height, alignment: .topLeading)
        .surface(cornerRadius: 22, isSelected: isSelected)
    }
}
