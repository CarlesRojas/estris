import SwiftUI

/// What clicking an overlay element does. Disabled (no-ops, no trash badges) outside the
/// overlay, such as in the settings preview.
struct OverlayActions {
    var pick: (ClipItem) -> Void = { _ in }
    var delete: (ClipItem) -> Void = { _ in }
    /// Clicking outside every element.
    var dismiss: () -> Void = {}
    var isEnabled = false
    var showsDate = true
    var showsDelete = true
    /// The quick-pick key for an entry, such as "⇧⌘1", or nil when it has none or they are hidden.
    var quickPickKey: (ClipItem) -> String? = { _ in nil }
    var showsQuickPickKeys = false

    /// Width elements keep free in their top-right corner for the date and trash button.
    var cornerReserve: CGFloat {
        guard isEnabled else { return 0 }
        let date: CGFloat = showsDate ? 92 : 0
        let delete: CGFloat = showsDelete ? 26 : 0
        let key: CGFloat = showsQuickPickKeys ? 34 : 0
        return date + delete + key
    }
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
    /// button that deletes it, each optional. Hovering tints the element a little.
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
                        if let key = actions.quickPickKey(item) {
                            Text(key)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.tertiary)
                                .frame(minHeight: 24)
                                .padding(.trailing, 6)
                        }
                        if actions.showsDate {
                            Text(dateTimeFormat.string(from: item.date))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                // Keeps the date clear of the corner when there is no trash button.
                                .frame(minHeight: 24)
                        }
                        if actions.showsDelete {
                            deleteButton
                        }
                    }
                    .padding(trashInset)
                }
                .animation(.easeOut(duration: 0.12), value: isHovered)
                .animation(.easeOut(duration: 0.12), value: isTrashHovered)
        } else {
            content
        }
    }

    private var deleteButton: some View {
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
