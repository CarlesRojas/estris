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
                    .opacity(opacity(distance, count: count))
                    // Offset does not move the layout frame, so the outer rotation pivots
                    // around the ring centre; the inner one keeps the chip upright.
                    .rotationEffect(.degrees(-angle))
                    .offset(y: -radius)
                    .rotationEffect(.degrees(angle))
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

    private func opacity(_ distance: Int, count: Int) -> Double {
        guard distance > 0 else { return 1 }
        let farthest = max(count / 2, 1)
        return 0.8 - 0.4 * Double(distance - 1) / Double(max(farthest - 1, 1))
    }
}

struct RingChip: View {
    let item: ClipItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            AppIconView(bundleID: item.sourceBundleID, size: 18)
            Text(item.text.singleLine)
                .font(.callout.weight(isSelected ? .semibold : .regular))
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
