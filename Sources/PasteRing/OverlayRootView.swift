import SwiftUI

struct OverlayRootView: View {
    @ObservedObject var state: OverlayState
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 16) {
            switch settings.style {
            case .stack: StackView(state: state)
            case .ring: RingMenuView(state: state)
            case .carousel: CarouselView(state: state)
            case .deck: DeckView(state: state)
            case .grid: GridView(state: state)
            }

            if !state.items.isEmpty {
                Text("\(state.selected + 1) of \(state.items.count)")
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(.regularMaterial, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}
