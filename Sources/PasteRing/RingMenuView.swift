import SwiftUI

/// Ring menu: every entry sits on one ring, evenly spaced. The ring turns so the
/// selected entry is at the top. It is an ellipse, as tight as the chips allow: wide chips
/// need room side by side at the top and bottom, but stack closely at the sides.
struct RingMenuView: View {
    private static let minRadius: CGFloat = 120
    private static let chipGap: CGFloat = 6
    /// Widest the ring may get relative to its height, so it still reads as a ring.
    private static let maxAspect: CGFloat = 1.6
    private static var radiiCache: [String: CGSize] = [:]

    @ObservedObject var state: OverlayState
    @ObservedObject var settings: AppSettings

    var body: some View {
        let count = state.items.count
        let step = count > 0 ? 360 / Double(count) : 0
        let chipWidth = settings.ringChipWidth
        let chipHeight = settings.ringChipHeight
        let radii = Self.radii(count: count, chipWidth: chipWidth, chipHeight: chipHeight)

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
                RingChip(item: item, isSelected: distance == 0, width: chipWidth, height: chipHeight)
                    .clipActions(item, trashInset: 6)
                    .modifier(RingPlacement(angle: angle, step: step, radii: radii))
                    .zIndex(distance == 0 ? 1 : 0)
            }
        }
        .frame(width: (radii.width + chipWidth * 0.6) * 2, height: (radii.height + chipHeight) * 2)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: state.position)
    }

    /// Smallest ellipse (horizontal and vertical radius) on which no two chips overlap.
    private static func radii(count: Int, chipWidth: CGFloat, chipHeight: CGFloat) -> CGSize {
        let key = "\(count)-\(Int(chipWidth))-\(Int(chipHeight))"
        if let cached = radiiCache[key] { return cached }

        // The chip at the top is drawn a little larger, so allow for that.
        let width = chipWidth * 1.04 + chipGap
        let height = chipHeight * 1.04 + chipGap
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

struct RingChip: View {
    let item: ClipItem
    let isSelected: Bool
    var width: CGFloat = 228
    var height: CGFloat = 56

    var body: some View {
        HStack(spacing: 10) {
            AppIconView(bundleID: item.sourceBundleID, size: 24)
            // No line limit: the text fills the chip and truncates where it ends.
            Text(item.text.singleLine)
                .font(.body)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                // Room for the trash button in the corner.
                .padding(.trailing, 16)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        // Every chip on the ring has the same size.
        .frame(width: width, height: height)
        .surface(cornerRadius: 18, isSelected: isSelected)
    }
}
