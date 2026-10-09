import SwiftUI

/// App icon and name on top, the copied text below, filling the card and truncating where
/// it ends. Used by Default and Stack.
struct EntryCard: View {
    let item: ClipItem?
    let width: CGFloat
    let height: CGFloat
    var isSelected = false
    @Environment(\.overlayActions) private var actions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let item {
                HStack(spacing: 10) {
                    SourceIcon(item: item, size: 28)
                    Text(item.sourceName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                // Room for the date and trash button in the corner.
                .padding(.trailing, actions.cornerReserve)
            }
            Group {
                if let item {
                    ClipContentView(item: item, font: .title3)
                } else {
                    Text("Clipboard history is empty")
                        .font(.title3)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(20)
        .frame(width: width, height: height)
        .surface(cornerRadius: 22, isSelected: isSelected)
    }
}
