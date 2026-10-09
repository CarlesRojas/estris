import SwiftUI

/// Every visible entry as a tile, all on screen at once.
struct GridView: View {
    @ObservedObject var state: OverlayState
    @ObservedObject var settings: ClipboardSettings

    private var layout: GridLayout {
        state.gridLayout ?? GridLayout.fitting(settings, in: CGSize(width: 10_000, height: 10_000))
    }

    var body: some View {
        let layout = layout
        Group {
            if state.items.isEmpty {
                ContentCard(item: nil, isSelected: true, width: 480, height: 160)
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(layout.tileWidth), spacing: layout.columnGap), count: GridLayout.columns),
                    spacing: layout.rowGap
                ) {
                    ForEach(state.items) { item in
                        let isSelected = item.id == state.selectedItem?.id
                        ContentCard(item: item, isSelected: isSelected, width: layout.tileWidth, height: layout.tileHeight, lineLimit: nil)
                            .clipActions(item, trashInset: 16)
                            .scaleEffect(isSelected ? GridLayout.selectedScale : 1)
                            .zIndex(isSelected ? 1 : 0)
                    }
                }
            }
        }
        .padding(GridLayout.padding)
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: state.selected)
    }
}
