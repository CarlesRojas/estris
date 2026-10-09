import SwiftUI

struct OverlayRootView: View {
    @ObservedObject var state: OverlayState
    @ObservedObject var settings: AppSettings
    @ObservedObject var appearance: AppearanceSettings

    var body: some View {
        ZStack {
            Color.black.opacity(appearance.backdropDim)
                // Clicking anywhere outside the elements closes the overlay.
                .contentShape(Rectangle())
                .onTapGesture { state.actions.dismiss() }
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environmentObject(appearance)
        .environment(\.overlayActions, state.actions)
    }

    private var content: some View {
        VStack(spacing: 16) {
            switch settings.style {
            case .stack: StackView(state: state, settings: settings)
            case .ring: RingMenuView(state: state)
            case .carousel: CarouselView(state: state, settings: settings)
            case .simple: SimpleView(state: state, settings: settings)
            case .grid: GridView(state: state, settings: settings)
            }

            if !state.items.isEmpty {
                PositionPill(text: "\(state.selected + 1) of \(state.items.count)")
            }
        }
    }
}

struct PositionPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium).monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .surface(cornerRadius: .infinity)
    }
}
