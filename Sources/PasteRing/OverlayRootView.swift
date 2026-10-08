import SwiftUI

struct OverlayRootView: View {
    @ObservedObject var state: OverlayState
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 16) {
            switch settings.style {
            case .stack: StackView(state: state)
            case .ring: RingMenuView(state: state)
            }

            Text(footer)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.regularMaterial, in: Capsule())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: String {
        let position = state.items.isEmpty ? "" : "\(state.selected + 1) of \(state.items.count) · "
        return position + "⌘⇧V, arrows or scroll to move · release to paste · ⌘⇧⎋ cancel"
    }
}
