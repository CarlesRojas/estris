import SwiftUI

/// Ring menu: every entry sits on one circle, evenly spaced. The ring turns so the
/// selected entry is at the top.
struct RingMenuView: View {
    private static let minRadius: CGFloat = 170
    /// Roughly a chip's width plus a gap, so neighbours at the top never overlap.
    private static let chipSpacing: CGFloat = 200

    @ObservedObject var state: OverlayState

    var body: some View {
        let count = state.items.count
        let step = count > 0 ? 360 / Double(count) : 0
        let radius = Self.radius(for: count)

        ZStack {
            if count == 0 {
                Text("Clipboard history is empty")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(state.items.enumerated()), id: \.element.id) { index, item in
                // Position is unbounded, so the angle keeps turning the same way past the last entry.
                let angle = Double(index - state.position) * step
                let distance = circularDistance(index, count: count)
                RingChip(item: item, isSelected: distance == 0)
                    .scaleEffect(distance == 0 ? 1.12 : 0.92)
                    .modifier(RingPlacement(angle: angle, radius: radius))
                    .zIndex(distance == 0 ? 1 : 0)
            }
        }
        .frame(width: (radius + 110) * 2, height: (radius + 40) * 2)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: state.position)
    }

    /// Large enough that the chord between neighbouring chips fits a chip.
    private static func radius(for count: Int) -> CGFloat {
        guard count > 2 else { return minRadius }
        return max(minRadius, chipSpacing / (2 * sin(.pi / CGFloat(count))))
    }

    private func circularDistance(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let forward = ((index - state.selected) % count + count) % count
        return min(forward, count - forward)
    }
}

/// Puts a chip on the circle with a plain offset, animating the angle so chips travel
/// along the arc. Avoids rotation transforms, which material backgrounds do not survive.
private struct RingPlacement: ViewModifier, Animatable {
    var angle: Double
    let radius: CGFloat

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        let radians = angle * .pi / 180
        return content.offset(x: radius * sin(radians), y: -radius * cos(radians))
    }
}

struct RingChip: View {
    let item: ClipItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            AppIconView(bundleID: item.sourceBundleID, size: 18)
            Text(item.text.singleLine)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 150)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .surface(cornerRadius: .infinity, isSelected: isSelected)
    }
}
