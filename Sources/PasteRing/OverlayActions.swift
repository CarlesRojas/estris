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
    /// Clicking pastes `item`; a trash badge on the top-right corner deletes it.
    func clipActions(_ item: ClipItem) -> some View {
        modifier(ClipActions(item: item))
    }
}

private struct ClipActions: ViewModifier {
    let item: ClipItem
    @Environment(\.overlayActions) private var actions

    @ViewBuilder
    func body(content: Content) -> some View {
        if actions.isEnabled {
            content
                .contentShape(Rectangle())
                .onTapGesture { actions.pick(item) }
                .overlay(alignment: .topTrailing) {
                    Button {
                        actions.delete(item)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.red.opacity(0.88))
                            .frame(width: 24, height: 24)
                            .background(.regularMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Delete from history")
                    .offset(x: 8, y: -8)
                }
        } else {
            content
        }
    }
}
