import SwiftUI

/// Ring menu: every entry sits on one oval, evenly spaced, and the oval turns so the
/// selected entry is at the top. The oval and the cards keep their size however many
/// entries there are: with more, cards simply overlap more, the ones nearer the top in
/// front of those further round.
struct RingMenuView: View {
    /// Oval radii as multiples of the card's width and height.
    private static let horizontalRadius: CGFloat = 1.6
    private static let verticalRadius: CGFloat = 0.9

    @ObservedObject var state: OverlayState
    @ObservedObject var settings: ClipboardSettings
    /// With Reduce Motion, the selection moves without sliding or springing.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let count = state.items.count
        let step = count > 0 ? 360 / Double(count) : 0
        let chipWidth = CGFloat(settings.ringChipWidth)
        let chipHeight = CGFloat(settings.ringChipHeight)
        let radii = CGSize(width: chipWidth * Self.horizontalRadius, height: chipHeight * Self.verticalRadius)
        // Fixed for a given card size: the enlarged top card and the pill above it reach
        // furthest from the centre; side cards are a little smaller than full size.
        let topReach = radii.height + chipHeight * RingPlacement.topScale / 2 + 46
        let size = CGSize(width: (radii.width + chipWidth * 0.55) * 2, height: topReach * 2)
        let scale = fitScale(for: size)

        ZStack {
            // Above the selected card at the top of the ring, which is drawn enlarged.
            if let position = state.positionText {
                PositionPill(text: position)
                    .offset(y: -radii.height - chipHeight * RingPlacement.topScale / 2 - 26)
            }

            if count == 0 {
                Text("Clipboard history is empty")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(state.items.enumerated()), id: \.element.id) { index, item in
                // Position is unbounded, so the angle keeps turning the same way past the last entry.
                let angle = Double(index - state.position) * step
                let distance = circularDistance(index, count: count)
                // Laid out like a grid tile: app on top, content below.
                ContentCard(item: item, isSelected: distance == 0, width: chipWidth, height: chipHeight, lineLimit: nil)
                    .clipActions(item, trashInset: 16)
                    .modifier(RingPlacement(angle: angle, step: step, radii: radii))
                    // Nearer the top is nearer the viewer: drawn over the cards further round.
                    .zIndex(Double(count - distance))
            }
        }
        .frame(width: size.width, height: size.height)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85), value: state.position)
        // A ring of tall cards can be bigger than the screen: shrink it as a whole to fit.
        .scaleEffect(scale)
        .frame(width: size.width * scale, height: size.height * scale)
    }

    private func fitScale(for size: CGSize) -> CGFloat {
        guard let screen = state.screenSize, size.width > 0, size.height > 0 else { return 1 }
        let margin: CGFloat = 60
        return min(1, (screen.width - margin) / size.width, (screen.height - margin) / size.height)
    }

    private func circularDistance(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let forward = ((index - state.selected) % count + count) % count
        return min(forward, count - forward)
    }
}

/// Placed with a plain offset, animating the angle so cards travel along the arc. Avoids
/// rotation transforms, which material backgrounds do not survive. A card grows as it nears
/// the top, so the selection swells in while it arrives.
/// The ring is seen at an angle: the top is nearest, so cards shrink as they go round
/// towards the bottom, and the selected card at the top is enlarged to about the size of
/// the Stack's front card.
struct RingPlacement: ViewModifier, Animatable {
    static let topScale: CGFloat = 1.3
    /// Size at the bottom of the ring, the furthest point.
    private static let farScale: CGFloat = 0.5
    /// How unevenly cards are spread: positive packs them closer together towards the
    /// bottom (further away, smaller) and spreads them out near the top. Below 1.
    private static let spacingSkew: Double = 0.2

    var angle: Double
    let step: Double
    /// Horizontal and vertical radius of the ellipse.
    let radii: CGSize

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        // Even slots, warped so they sit closer together the further round they are:
        // the gap between neighbours grows by (1 + skew) at the top and shrinks by
        // (1 - skew) at the bottom, and the top and bottom stay where they are.
        let even = remainder(angle, 360) * .pi / 180
        let radians = even + Self.spacingSkew * sin(even)
        // Angle from the top, in -180...180, since the raw angle keeps growing as the ring turns.
        let fromTop = abs(remainder(angle, 360))
        let nearness = step > 0 ? CGFloat(max(0, 1 - fromTop / step)) : 1
        // 1 at the top, 0 at the bottom.
        let depth = CGFloat((1 + cos(radians)) / 2)
        let ringScale = Self.farScale + (1 - Self.farScale) * depth
        return content
            .scaleEffect(ringScale + (Self.topScale - 1) * nearness)
            .offset(x: radii.width * sin(radians), y: -radii.height * cos(radians))
    }
}
