import SwiftUI

struct OverlayRootView: View {
    @ObservedObject var state: OverlayState
    @ObservedObject var settings: ClipboardSettings
    @ObservedObject var appearance: AppearanceSettings
    @ObservedObject var general: GeneralSettings

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
        .environment(\.overlayActions, actions)
        .environment(\.dateTimeFormat, general.dateTimeFormat)
    }

    private var actions: OverlayActions {
        var actions = state.actions
        actions.showsDate = settings.showCopyDate
        actions.showsDelete = settings.showDeleteButton
        return actions
    }

    private var content: some View {
        VStack(spacing: 16) {
            switch settings.style {
            case .stack: StackView(state: state, settings: settings)
            case .ring: RingMenuView(state: state, settings: settings)
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
