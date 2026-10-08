import SwiftUI

/// Ring menu: entries sit on a circle that rotates so the selected one is at the top,
/// with its full text shown in the centre.
struct RingMenuView: View {
    private static let radius: CGFloat = 210
    private static let trackWidth: CGFloat = 56
    private static let slotAngle: Double = 45
    private static let visibleRange = 3

    @ObservedObject var state: OverlayState

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(.ultraThinMaterial, lineWidth: Self.trackWidth)
                .frame(width: (Self.radius + Self.trackWidth / 2) * 2, height: (Self.radius + Self.trackWidth / 2) * 2)

            centerCard

            ForEach(state.circularSlots(within: -Self.visibleRange...Self.visibleRange)) { slot in
                let angle = Double(slot.distance) * Self.slotAngle
                RingChip(item: slot.item, isSelected: slot.distance == 0)
                    .scaleEffect(scale(slot.distance))
                    .opacity(opacity(slot.distance))
                    // Offset does not move the layout frame, so the outer rotation pivots
                    // around the ring centre; the inner one keeps the chip upright.
                    .rotationEffect(.degrees(-angle))
                    .offset(y: -Self.radius)
                    .rotationEffect(.degrees(angle))
                    .zIndex(Double(-abs(slot.distance)))
                    .transition(.opacity)
            }
        }
        .frame(width: 640, height: 560)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: state.position)
    }

    private var centerCard: some View {
        let item = state.selectedItem
        return HStack(alignment: .top, spacing: 12) {
            if let item {
                AppIconView(bundleID: item.sourceBundleID, size: 32)
            }
            Text(item?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Clipboard history is empty")
                .font(.system(size: 16, weight: .medium))
                .lineLimit(6)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: item == nil ? .center : .leading)
        }
        .frame(width: 260)
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 14, y: 4)
    }

    private func scale(_ distance: Int) -> CGFloat {
        let scales: [CGFloat] = [1.0, 0.85, 0.72, 0.6]
        return scales[min(abs(distance), 3)]
    }

    private func opacity(_ distance: Int) -> Double {
        let opacities: [Double] = [1.0, 0.6, 0.35, 0.15]
        return opacities[min(abs(distance), 3)]
    }
}

private struct RingChip: View {
    let item: ClipItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            AppIconView(bundleID: item.sourceBundleID, size: 18)
            Text(item.text.singleLine)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 150)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: .black.opacity(isSelected ? 0.3 : 0.1), radius: isSelected ? 10 : 4, y: 2)
    }
}
