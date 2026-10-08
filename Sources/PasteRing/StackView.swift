import SwiftUI

/// Vertical stack: the selected entry in the middle, neighbours above and below.
struct StackView: View {
    private static let visibleRange = 3

    private static let spacing: CGFloat = 8
    private static let fallbackHeight: CGFloat = 50

    @ObservedObject var state: OverlayState
    @State private var heights: [UUID: CGFloat] = [:]

    var body: some View {
        ZStack {
            if state.items.isEmpty {
                ClipCard(text: "Clipboard history is empty", isSelected: true, showsIcon: false)
            } else {
                ForEach(Array(state.items.enumerated()), id: \.element.id) { index, item in
                    let distance = index - state.selected
                    if abs(distance) <= Self.visibleRange {
                        ClipCard(text: item.text, isSelected: distance == 0, appBundleID: item.sourceBundleID)
                            .background(GeometryReader { proxy in
                                Color.clear.preference(key: CardHeights.self, value: [item.id: proxy.size.height])
                            })
                            .scaleEffect(scale(distance))
                            .opacity(opacity(distance))
                            .offset(y: offset(for: index))
                            .zIndex(Double(-abs(distance)))
                    }
                }
            }
        }
        .frame(width: 640, height: 480)
        .onPreferenceChange(CardHeights.self) { heights = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: state.selected)
    }

    private func scale(_ distance: Int) -> CGFloat {
        let scales: [CGFloat] = [1.0, 0.8, 0.68, 0.58]
        return scales[min(abs(distance), 3)]
    }

    private func opacity(_ distance: Int) -> Double {
        let opacities: [Double] = [1.0, 0.55, 0.3, 0.12]
        return opacities[min(abs(distance), 3)]
    }

    /// Stacks cards edge to edge (after scaling) outward from the selected one.
    private func offset(for index: Int) -> CGFloat {
        let step = index > state.selected ? 1 : -1
        var y: CGFloat = 0
        var current = state.selected
        while current != index {
            let next = current + step
            y += halfHeight(current) + halfHeight(next) + Self.spacing
            current = next
        }
        return CGFloat(step) * y
    }

    private func halfHeight(_ index: Int) -> CGFloat {
        let height = heights[state.items[index].id] ?? Self.fallbackHeight
        return height * scale(index - state.selected) / 2
    }
}

private struct CardHeights: PreferenceKey {
    static let defaultValue: [UUID: CGFloat] = [:]

    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

struct ClipCard: View {
    let text: String
    let isSelected: Bool
    var appBundleID: String?
    var showsIcon = true

    var body: some View {
        HStack(spacing: 14) {
            if showsIcon {
                AppIconView(bundleID: appBundleID, size: 30)
            }
            Text(displayText)
                .font(isSelected ? .title3.weight(.semibold) : .body)
                .lineLimit(isSelected ? 4 : 1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 520, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .surface(RoundedRectangle(cornerRadius: 20, style: .continuous), isSelected: isSelected)
    }

    /// Unselected cards show one line, so collapse newlines to keep the preview meaningful.
    private var displayText: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return isSelected ? trimmed : text.singleLine
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
