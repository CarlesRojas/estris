import SwiftUI

/// Every visible entry as a tile, all on screen at once.
struct GridView: View {
    private static let tileHeight: CGFloat = 130
    private static let selectedScale: CGFloat = 1.06
    /// Clearance left between the enlarged selected tile and its neighbours.
    private static let clearance: CGFloat = 10

    @ObservedObject var state: OverlayState
    @ObservedObject var settings: AppSettings

    /// Grows with the tile size, so the enlarged selected tile never reaches its neighbours.
    /// Only the selected tile grows, so it alone eats into each gap.
    private var columnGap: CGFloat {
        settings.gridCardWidth * (Self.selectedScale - 1) / 2 + Self.clearance
    }

    private var rowGap: CGFloat {
        Self.tileHeight * (Self.selectedScale - 1) / 2 + Self.clearance
    }

    var body: some View {
        Group {
            if state.items.isEmpty {
                ContentCard(item: nil, isSelected: true, width: 480, height: 160)
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(settings.gridCardWidth), spacing: columnGap), count: AppSettings.gridColumns),
                    spacing: max(rowGap, 14)
                ) {
                    ForEach(state.items) { item in
                        let isSelected = item.id == state.selectedItem?.id
                        ContentCard(item: item, isSelected: isSelected, width: settings.gridCardWidth, height: Self.tileHeight, lineLimit: 3)
                            .clipActions(item, trashInset: 16)
                            .scaleEffect(isSelected ? Self.selectedScale : 1)
                            .zIndex(isSelected ? 1 : 0)
                    }
                }
            }
        }
        .padding(20)
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: state.selected)
    }
}
