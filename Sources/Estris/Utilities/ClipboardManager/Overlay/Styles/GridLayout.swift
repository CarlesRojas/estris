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
