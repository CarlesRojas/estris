import SwiftUI

/// Vertical wheel: entries ride a circle that curves away from you, so the next one comes
/// forward and up into the front. Cards always face you; depth shows as size and overlap.
struct StackView: View {
    private static let visibleRange = 3
    /// Angle between neighbouring entries on the wheel, in degrees.
    private static let step: Double = 26
    private static let radius: CGFloat = 230
    /// Distance from the viewer to the front of the wheel. Smaller means stronger depth.
    private static let perspective: CGFloat = 320

    @ObservedObject var state: OverlayState

    var body: some View {
        ZStack {
            if state.items.isEmpty {
                ClipCard(text: "Clipboard history is empty", isSelected: true, showsIcon: false)
            } else {
                ForEach(Array(state.items.enumerated()), id: \.element.id) { index, item in
                    let distance = index - state.selected
                    if abs(distance) <= Self.visibleRange {
                        ClipCard(text: item.text, isSelected: distance == 0, appBundleID: item.sourceBundleID)
                            .modifier(WheelPlacement(
                                angle: Double(distance) * Self.step,
                                radius: Self.radius,
                                perspective: Self.perspective
                            ))
                            .zIndex(Double(-abs(distance)))
                    }
                }
            }
        }
        .frame(width: 640, height: 560)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: state.selected)
    }
}

/// Places a card on the wheel. Animating the angle (not the resulting offset and scale)
/// makes cards travel along the curve instead of in a straight line.
private struct WheelPlacement: ViewModifier, Animatable {
    var angle: Double
    let radius: CGFloat
    let perspective: CGFloat

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        let radians = angle * .pi / 180
        let depth = radius * (1 - cos(radians))
        return content
            .scaleEffect(perspective / (perspective + depth))
            .offset(y: radius * sin(radians))
    }
}

struct ClipCard: View {
    let text: String
    let isSelected: Bool
    var appBundleID: String?
    var showsIcon = true

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            if showsIcon {
                AppIconView(bundleID: appBundleID, size: 30)
            }
            // Same font and line limit front and back, so nothing reflows as a card moves.
            Text(text.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.title3)
                .lineLimit(4)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 520, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .surface(cornerRadius: 20, isSelected: isSelected)
    }
}

extension String {
    /// Trimmed, with line breaks shown as ⏎ so one-line previews stay meaningful.
    var singleLine: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ⏎ ")
    }
}
