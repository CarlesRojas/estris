import SwiftUI

/// Fixed-size card with the source app and the text, shared by Carousel and Grid.
struct ContentCard: View {
    let item: ClipItem?
    let isSelected: Bool
    @Environment(\.overlayActions) private var actions
    var width: CGFloat = 260
    var height: CGFloat = 260
    var lineLimit: Int? = 9

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let item {
                HStack(spacing: 8) {
                    SourceIcon(item: item, size: 24)
                    Text(item.sourceName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                // Room for the date and trash button in the corner.
                .padding(.trailing, actions.cornerReserve)
                // Same font whether selected or not: a heavier weight rewraps the text.
                ClipContentView(item: item)
                    .lineLimit(lineLimit)
            } else {
                Text("Clipboard history is empty")
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: width, height: height, alignment: .topLeading)
        .surface(cornerRadius: 22, isSelected: isSelected)
    }
}
