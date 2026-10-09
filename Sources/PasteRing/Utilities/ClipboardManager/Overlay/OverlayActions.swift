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

    /// Width elements keep free in their top-right corner for the date and trash button.
    var cornerReserve: CGFloat {
        guard isEnabled else { return 0 }
        let date: CGFloat = showsDate ? 92 : 0
        let delete: CGFloat = showsDelete ? 26 : 0
        return date + delete
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
                    // Aligned on the text baseline, so the date sits level with the
                    // trash symbol instead of riding above it.
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        if actions.showsDate {
                            Text(dateTimeFormat.string(from: item.date))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if actions.showsDelete {
                            deleteButton
                        }
                    }
                    // Same height as the trash button even without it, so the row lines up.
                    .frame(minHeight: 24)
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
                .foregroundStyle(isTrashHovered ? .primary : .secondary)
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
