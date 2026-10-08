import SwiftUI

struct RingView: View {
    static let size = CGSize(width: 640, height: 480)
    private static let visibleRange = 3

    @ObservedObject var state: OverlayState

    var body: some View {
        ZStack {
            if state.items.isEmpty {
                ClipCard(text: "Clipboard history is empty", isSelected: true)
            } else {
                ForEach(Array(state.items.enumerated()), id: \.element.id) { index, item in
                    let distance = index - state.selected
                    if abs(distance) <= Self.visibleRange {
                        ClipCard(text: item.text, isSelected: distance == 0)
                            .scaleEffect(scale(distance))
                            .opacity(opacity(distance))
                            .offset(y: offset(distance))
                            .zIndex(Double(-abs(distance)))
                    }
                }
            }

            VStack {
                Spacer()
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.regularMaterial, in: Capsule())
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: state.selected)
    }

    private var footer: String {
        let position = state.items.isEmpty ? "" : "\(state.selected + 1) of \(state.items.count) · "
        return position + "⌘⇧V next · release to paste · ⌘⇧⎋ cancel"
    }

    private func scale(_ distance: Int) -> CGFloat {
        let scales: [CGFloat] = [1.0, 0.8, 0.68, 0.58]
        return scales[min(abs(distance), 3)]
    }

    private func opacity(_ distance: Int) -> Double {
        let opacities: [Double] = [1.0, 0.55, 0.3, 0.12]
        return opacities[min(abs(distance), 3)]
    }

    private func offset(_ distance: Int) -> CGFloat {
        let magnitude: CGFloat = [0, 95, 150, 195][min(abs(distance), 3)]
        return distance < 0 ? -magnitude : magnitude
    }
}

struct ClipCard: View {
    let text: String
    let isSelected: Bool

    var body: some View {
        Text(displayText)
            .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
            .lineLimit(isSelected ? 4 : 1)
            .truncationMode(.tail)
            .frame(width: 520, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: .black.opacity(isSelected ? 0.3 : 0.1), radius: isSelected ? 16 : 6, y: 4)
    }

    /// Unselected cards show one line, so collapse newlines to keep the preview meaningful.
    private var displayText: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return isSelected ? trimmed : trimmed.split(whereSeparator: \.isNewline).joined(separator: " ⏎ ")
    }
}
