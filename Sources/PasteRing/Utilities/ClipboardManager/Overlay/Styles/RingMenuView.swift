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
    @Environment(\.overlayActions) private var actions

    var body: some View {
        let count = state.items.count
        let step = count > 0 ? 360 / Double(count) : 0
        let chipWidth = CGFloat(settings.ringChipWidth)
        let chipHeight = CGFloat(settings.ringChipHeight)
        // Chips holding an image are taller; the ring is spaced for the tallest one.
        let heights: [CGFloat] = state.items.map {
            RingChip.fittedHeight(for: $0, width: chipWidth, height: chipHeight, cornerReserve: actions.cornerReserve)
        }
        let layoutHeight = heights.max() ?? chipHeight
        let radii = Self.radii(count: count, chipWidth: chipWidth, chipHeight: layoutHeight)
        let selectedHeight = heights.indices.contains(state.selected) ? heights[state.selected] : chipHeight

        ZStack {
            // Above the selected chip at the top of the ring (drawn 1.12 times larger there).
            if let position = state.positionText {
                PositionPill(text: position)
                    .offset(y: -radii.height - selectedHeight * 1.12 / 2 - 26)
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
                RingChip(item: item, isSelected: distance == 0, width: chipWidth, height: chipHeight)
                    .clipActions(item, trashInset: 6)
                    .modifier(RingPlacement(angle: angle, step: step, radii: radii))
                    .zIndex(distance == 0 ? 1 : 0)
            }
        }
        .frame(width: (radii.width + chipWidth * 0.6) * 2, height: (radii.height + layoutHeight + 30) * 2)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: state.position)
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

/// Puts a chip on the circle with a plain offset, animating the angle so chips travel
/// along the arc. Avoids rotation transforms, which material backgrounds do not survive.
/// A chip grows as it nears the top, so the selection swells in while it arrives.
private struct RingPlacement: ViewModifier, Animatable {
    private static let topScale: CGFloat = 1.12
    private static let restScale: CGFloat = 0.92

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
        return content
            .scaleEffect(Self.restScale + (Self.topScale - Self.restScale) * nearness)
            .offset(x: radii.width * sin(radians), y: -radii.height * cos(radians))
    }
}
