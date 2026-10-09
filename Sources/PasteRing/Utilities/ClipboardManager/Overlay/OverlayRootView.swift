import SwiftUI

struct OverlayRootView: View {
    @ObservedObject var state: OverlayState
    @ObservedObject var settings: ClipboardSettings
    @ObservedObject var appearance: AppearanceSettings
    @ObservedObject var general: GeneralSettings
    @State private var growth: CGFloat = 0

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
        actions.showsQuickPickKeys = settings.showQuickPickKeys
        if settings.showQuickPickKeys {
            let items = state.items
            let modifiers = state.activeShortcut.modifierSymbols
            actions.quickPickKey = { item in
                guard let index = items.firstIndex(where: { $0.id == item.id }), index < 9 else { return nil }
                return "\(modifiers)\(index + 1)"
            }
        }
        return actions
    }

    private var content: some View {
        style
            .onPreferenceChange(OverlayGrowthKey.self) { growth = max(0, $0) }
            // The pill hangs below the style without taking part in its layout, so the style
            // stays put on screen; it moves down when a card grows for an image.
            .overlay(alignment: .bottom) {
                if !state.items.isEmpty {
                    PositionPill(text: "\(state.selected + 1) of \(state.items.count)")
                        .alignmentGuide(.bottom) { pill in pill[.top] - 16 - growth }
                }
            }
    }

    @ViewBuilder
    private var style: some View {
        switch settings.style {
        case .stack: StackView(state: state, settings: settings)
        case .ring: RingMenuView(state: state, settings: settings)
        case .carousel: CarouselView(state: state, settings: settings)
        case .simple: SimpleView(state: state, settings: settings)
        case .grid: GridView(state: state, settings: settings)
        }
    }
}
