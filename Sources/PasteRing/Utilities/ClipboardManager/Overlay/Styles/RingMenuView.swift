import SwiftUI

/// Ring menu: every entry sits on one ring, evenly spaced. The ring turns so the
/// selected entry is at the top. It is an ellipse, as tight as the chips allow: wide chips
/// need room side by side at the top and bottom, but stack closely at the sides.
struct RingMenuView: View {
    private static let minRadius: CGFloat = 120
    private static let chipGap: CGFloat = 4
    /// Widest the ring may get relative to its height, so it still reads as a ring.
    private static let maxAspect: CGFloat = 2.2
    private static var radiiCache: [String: CGSize] = [:]

    @ObservedObject var state: OverlayState
    @ObservedObject var settings: ClipboardSettings

    var body: some View {
        let count = state.items.count
        let step = count > 0 ? 360 / Double(count) : 0
        let chipWidth = CGFloat(settings.ringChipWidth)
        let chipHeight = CGFloat(settings.ringChipHeight)
        let radii = Self.radii(count: count, chipWidth: chipWidth, chipHeight: chipHeight)
        // Room for the enlarged card at the top and the pill above it.
        let topExtra = chipHeight * (RingPlacement.topScale - 1)
        let size = CGSize(
            width: max((radii.width + chipWidth * 0.6) * 2, chipWidth * RingPlacement.topScale),
            height: (radii.height + chipHeight + 30) * 2 + topExtra * 2
        )
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
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: state.position)
        // A ring of tall cards can be bigger than the screen: shrink it as a whole to fit.
        .scaleEffect(scale)
        .frame(width: size.width * scale, height: size.height * scale)
    }

    private func fitScale(for size: CGSize) -> CGFloat {
        guard let screen = state.screenSize, size.width > 0, size.height > 0 else { return 1 }
        let margin: CGFloat = 60
        return min(1, (screen.width - margin) / size.width, (screen.height - margin) / size.height)
    }

    /// Smallest ellipse (horizontal and vertical radius) on which no two chips overlap.
    private static func radii(count: Int, chipWidth: CGFloat, chipHeight: CGFloat) -> CGSize {
        let key = "\(count)-\(Int(chipWidth))-\(Int(chipHeight))"
        if let cached = radiiCache[key] { return cached }

        // Chips may touch the enlarged top chip slightly; it is drawn above its neighbours.
        let width = chipWidth + chipGap
        let height = chipHeight + chipGap
        let angles = (0..<count).map { 2 * Double.pi * Double($0) / Double(count) }

        func fits(_ rx: CGFloat, _ ry: CGFloat) -> Bool {
            let points = angles.map { CGPoint(x: rx * sin($0), y: -ry * cos($0)) }
            for i in points.indices {
                for j in points.indices where j > i {
                    if abs(points[i].x - points[j].x) < width && abs(points[i].y - points[j].y) < height {
                        return false
                    }
                }
            }
            return true
        }

        var result = CGSize(width: minRadius, height: minRadius)
        search: for ry in stride(from: minRadius, through: 2000, by: 4) {
            for rx in stride(from: ry, through: ry * maxAspect, by: 4) where fits(rx, ry) {
                result = CGSize(width: rx, height: ry)
                break search
            }
        }
        radiiCache[key] = result
        return result
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
    static let topScale: CGFloat = 1.6
    /// Size at the bottom of the ring, the furthest point.
    private static let farScale: CGFloat = 0.5

    var angle: Double
    let step: Double
    /// Horizontal and vertical radius of the ellipse.
    let radii: CGSize

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        let radians = angle * .pi / 180
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
