import SwiftUI

/// Every visible entry as a tile, all on screen at once.
struct GridView: View {
    @ObservedObject var state: OverlayState
    @ObservedObject var settings: AppSettings

    var body: some View {
        Group {
            if state.items.isEmpty {
                ContentCard(item: nil, isSelected: true, width: 480, height: 160)
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(settings.gridCardWidth), spacing: 14), count: AppSettings.gridColumns),
                    spacing: 14
                ) {
                    ForEach(state.items) { item in
                        let isSelected = item.id == state.selectedItem?.id
                        ContentCard(item: item, isSelected: isSelected, width: settings.gridCardWidth, height: 130, lineLimit: 3)
                            .clipActions(item)
                            .scaleEffect(isSelected ? 1.06 : 1)
                            .zIndex(isSelected ? 1 : 0)
                    }
                }
            }
        }
        .padding(20)
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: state.selected)
    }
}
