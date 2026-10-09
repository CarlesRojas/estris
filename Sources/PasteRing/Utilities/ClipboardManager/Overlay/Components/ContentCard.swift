import SwiftUI

/// Fixed-size card with the source app and the text, shared by Carousel and Grid.
struct ContentCard: View {
    let item: ClipItem?
    let isSelected: Bool
    @Environment(\.overlayActions) private var actions
    var width: CGFloat = 260
    var height: CGFloat = 260
    var lineLimit: Int? = 9
    /// Grow taller for an image so it shows whole (the grid keeps its rows even instead).
    var growsToFitImage = false

    private static let padding: CGFloat = 16
    /// Padding plus the app row and the gap below it.
    private static let chrome: CGFloat = padding * 2 + 24 + 10

    static func fittedHeight(for item: ClipItem?, width: CGFloat, height: CGFloat) -> CGFloat {
        ImageFitting.cardHeight(for: item, baseHeight: height, contentWidth: width - padding * 2, chrome: chrome)
    }

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
                ClipContentView(item: item, fitsImageInside: !growsToFitImage)
                    .lineLimit(lineLimit)
            } else {
                Text("Clipboard history is empty")
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Spacer(minLength: 0)
        }
        .padding(Self.padding)
        .frame(width: width, height: growsToFitImage ? Self.fittedHeight(for: item, width: width, height: height) : height, alignment: .topLeading)
        .surface(cornerRadius: 22, isSelected: isSelected)
    }
}
