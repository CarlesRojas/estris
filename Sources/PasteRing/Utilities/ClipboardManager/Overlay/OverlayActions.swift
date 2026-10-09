import SwiftUI

/// What clicking an overlay element does. Disabled (no-ops, no trash badges) outside the
/// overlay, such as in the settings preview.
struct OverlayActions {
    var pick: (ClipItem) -> Void = { _ in }
    var delete: (ClipItem) -> Void = { _ in }
    /// Clicking outside every element.
    var dismiss: () -> Void = {}
    var isEnabled = false
}

private struct OverlayActionsKey: EnvironmentKey {
    static let defaultValue = OverlayActions()
}

extension EnvironmentValues {
    var overlayActions: OverlayActions {
        get { self[OverlayActionsKey.self] }
        set { self[OverlayActionsKey.self] = newValue }
    }
}

extension View {
    /// Clicking pastes `item`. The top-right corner shows when it was copied and a trash
/// button that deletes it. Hovering tints the element a little.
    /// `trashInset` lines the date and button up with the element's first row.
    func clipActions(_ item: ClipItem, trashInset: CGFloat = 12) -> some View {
        modifier(ClipActions(item: item, trashInset: trashInset))
    }
}

private struct ClipActions: ViewModifier {
    let item: ClipItem
    let trashInset: CGFloat
    @Environment(\.overlayActions) private var actions
    @Environment(\.dateTimeFormat) private var dateTimeFormat
    @State private var isHovered = false
    @State private var isTrashHovered = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if actions.isEnabled {
            content
                .environment(\.surfaceHovered, isHovered)
                .contentShape(Rectangle())
                .onHover { isHovered = $0 }
                .onTapGesture { actions.pick(item) }
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: 2) {
                        Text(dateTimeFormat.string(from: item.date))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                        Button {
                            actions.delete(item)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(isTrashHovered ? .primary : .tertiary)
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .onHover { isTrashHovered = $0 }
                        .help("Delete from history")
                    }
                    .padding(trashInset)
                }
                .animation(.easeOut(duration: 0.12), value: isHovered)
                .animation(.easeOut(duration: 0.12), value: isTrashHovered)
        } else {
            content
        }
    }
}

private struct SurfaceHoveredKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// The pointer is over this element; its surface gets a little more tint.
    var surfaceHovered: Bool {
        get { self[SurfaceHoveredKey.self] }
        set { self[SurfaceHoveredKey.self] = newValue }
    }
}
