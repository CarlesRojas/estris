import SwiftUI

/// Tile sizes and gaps for the grid, fitted to the screen it opens on.
struct GridLayout: Equatable {
    static let columns = 4
    static let selectedScale: CGFloat = 1.06
    /// Clearance left between the enlarged selected tile and its neighbours.
    static let clearance: CGFloat = 10
    static let padding: CGFloat = 20
    /// Room kept free for the position pill and a margin around the grid.
    static let reservedSize = CGSize(width: 80, height: 140)

    let tileWidth: CGFloat
    let tileHeight: CGFloat
    /// Rows shown: the configured amount, or fewer when that many would not fit.
    let rows: Int

    /// Grows with the tile size, so the enlarged selected tile never reaches its neighbours.
    /// Only the selected tile grows, so it alone eats into each gap.
    var columnGap: CGFloat { tileWidth * (Self.selectedScale - 1) / 2 + Self.clearance }
    var rowGap: CGFloat { max(tileHeight * (Self.selectedScale - 1) / 2 + Self.clearance, 14) }

    /// Narrows tiles that would overflow the screen width, and drops rows that would
    /// overflow its height.
    @MainActor
    static func fitting(_ settings: ClipboardSettings, in screen: CGSize) -> GridLayout {
        let columns = CGFloat(Self.columns)
        let available = CGSize(
            width: screen.width - reservedSize.width - padding * 2,
            height: screen.height - reservedSize.height - padding * 2
        )
        let growth = (selectedScale - 1) / 2
        // columns * w + (columns - 1) * (w * growth + clearance) <= available width
        let widestFit = (available.width - (columns - 1) * clearance) / (columns + (columns - 1) * growth)
        let tileWidth = max(80, min(settings.gridCardWidth, widestFit))
        let tileHeight = settings.gridCardHeight

        let rowGap = max(tileHeight * growth + clearance, 14)
        let rowsThatFit = Int((available.height + rowGap) / (tileHeight + rowGap))
        let rows = max(1, min(settings.gridSize / Self.columns, rowsThatFit))
        return GridLayout(tileWidth: tileWidth, tileHeight: tileHeight, rows: rows)
    }
}

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
