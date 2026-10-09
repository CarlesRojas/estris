import SwiftUI

/// Cover Flow style: the selected card faces you, the others tilt away on either side.
/// Tilted cards are solid, since glass and blur break under the 3D tilt.
struct CarouselView: View {
    private static let visibleRange = 3

    @ObservedObject var state: OverlayState

    var body: some View {
        ZStack {
            if state.items.isEmpty {
                ContentCard(item: nil, isSelected: true)
            } else {
                ForEach(Array(state.items.enumerated()), id: \.element.id) { index, item in
                    let distance = index - state.selected
                    if abs(distance) <= Self.visibleRange {
                        ContentCard(item: item, isSelected: distance == 0)
                            // Backdrop effects break under the 3D tilt, so only the front card uses one.
                            .environment(\.surfaceIsSolid, distance != 0)
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
        .frame(width: 900, height: 340)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: state.selected)
    }

    private func offset(_ distance: Int) -> CGFloat {
        guard distance != 0 else { return 0 }
        let magnitude = 190 + CGFloat(abs(distance) - 1) * 80
        return distance < 0 ? -magnitude : magnitude
    }
}

/// Fixed-size card with the source app and the text, shared by Carousel and Grid.
struct ContentCard: View {
    let item: ClipItem?
    let isSelected: Bool
    var width: CGFloat = 260
    var height: CGFloat = 260
    var lineLimit = 9

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
                Text(item.text.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.body.weight(isSelected ? .medium : .regular))
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
