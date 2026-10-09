import SwiftUI

/// Ring menu: every entry sits on one circle, evenly spaced. The ring turns so the
/// selected entry is at the top.
struct RingMenuView: View {
    private static let minRadius: CGFloat = 170
    /// Roughly a chip's width plus a gap, so neighbours at the top never overlap.
    private static let chipSpacing: CGFloat = 238

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
                    .clipActions(item)
                    .modifier(RingPlacement(angle: angle, step: step, radius: radius))
                    .zIndex(distance == 0 ? 1 : 0)
            }
        }
        .frame(width: (radius + 130) * 2, height: (radius + 50) * 2)
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
/// A chip grows as it nears the top, so the selection swells in while it arrives.
private struct RingPlacement: ViewModifier, Animatable {
    private static let topScale: CGFloat = 1.12
    private static let restScale: CGFloat = 0.92

    var angle: Double
    let step: Double
    let radius: CGFloat

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        let radians = angle * .pi / 180
        // Angle from the top, in -180...180, since the raw angle keeps growing as the ring turns.
        let fromTop = abs(remainder(angle, 360))
        let nearness = step > 0 ? CGFloat(max(0, 1 - fromTop / step)) : 1
        return content
            .scaleEffect(Self.restScale + (Self.topScale - Self.restScale) * nearness)
            .offset(x: radius * sin(radians), y: -radius * cos(radians))
    }
}

struct RingChip: View {
    let item: ClipItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            AppIconView(bundleID: item.sourceBundleID, size: 24)
            Text(item.text.singleLine)
                .font(.body)
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Fixed size, two lines tall, so every chip on the ring matches.
        .frame(width: 200, height: 36)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .surface(cornerRadius: 18, isSelected: isSelected)
    }
}
