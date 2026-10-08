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

            ForEach(slots) { slot in
                let angle = Double(slot.distance) * Self.slotAngle
                RingChip(text: slot.item.text, isSelected: slot.distance == 0)
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
        let text = state.items.indices.contains(state.selected)
            ? state.items[state.selected].text.trimmingCharacters(in: .whitespacesAndNewlines)
            : "Clipboard history is empty"
        return Text(text)
            .font(.system(size: 16, weight: .medium))
            .lineLimit(6)
            .truncationMode(.tail)
            .multilineTextAlignment(.center)
            .frame(width: 260)
            .padding(18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 14, y: 4)
    }

    private struct Slot: Identifiable {
        let id: String
        let item: ClipItem
        let distance: Int
    }

    /// Places each entry at its circular distance from the selection. `lap` is part of
    /// the identity, so an entry that wraps to the other side of the ring fades out and
    /// back in instead of sweeping across the top.
    private var slots: [Slot] {
        let count = state.items.count
        guard count > 0 else { return [] }
        let lowest = -(count - 1) / 2
        return state.items.enumerated().compactMap { index, item in
            let raw = index - state.position
            let shifted = raw - lowest
            let lap = shifted >= 0 ? shifted / count : -((-shifted + count - 1) / count)
            let distance = raw - lap * count
            guard abs(distance) <= Self.visibleRange else { return nil }
            return Slot(id: "\(item.id)-\(lap)", item: item, distance: distance)
        }
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
    let text: String
    let isSelected: Bool

    var body: some View {
        Text(text.singleLine)
            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
            .lineLimit(1)
            .truncationMode(.tail)
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
