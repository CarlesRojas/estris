import SwiftUI

/// Pages of tiles; the page follows the selection.
struct GridView: View {
    private static let columns = 4
    private static let rows = 3
    private static let pageSize = columns * rows

    @ObservedObject var state: OverlayState

    var body: some View {
        Group {
            if state.items.isEmpty {
                ContentCard(item: nil, isSelected: true, width: 480, height: 160)
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(200), spacing: 14), count: Self.columns),
                    spacing: 14
                ) {
                    ForEach(pageItems) { item in
                        let isSelected = item.id == state.selectedItem?.id
                        ContentCard(item: item, isSelected: isSelected, width: 200, height: 130, lineLimit: 3)
                            .scaleEffect(isSelected ? 1.06 : 1)
                            .opacity(isSelected ? 1 : 0.7)
                            .zIndex(isSelected ? 1 : 0)
                    }
                }
            }
        }
        .frame(width: 880, height: 460)
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: state.selected)
    }

    private var pageItems: [ClipItem] {
        let start = state.selected / Self.pageSize * Self.pageSize
        return Array(state.items[start..<min(start + Self.pageSize, state.items.count)])
    }
}
