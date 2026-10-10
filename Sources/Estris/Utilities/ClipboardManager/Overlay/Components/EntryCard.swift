import SwiftUI

/// App icon and name on top, the copied text below, filling the card and truncating where
/// it ends. Used by Default and Stack.
struct EntryCard: View {
    let item: ClipItem?
    let width: CGFloat
    let height: CGFloat
    var isSelected = false
    /// Grow taller so an image shows whole at the card's width (Default); otherwise the image
    /// fits inside the card as it is (Stack).
    var growsToFitImage = false
    @Environment(\.overlayActions) private var actions

    private static let padding: CGFloat = 20
    /// Padding plus the app row and the gap below it.
    private static let chrome: CGFloat = padding * 2 + 28 + 12

    /// `height`, or taller for an image so it shows whole at the card's width.
    static func fittedHeight(for item: ClipItem?, width: CGFloat, height: CGFloat) -> CGFloat {
        ImageFitting.cardHeight(for: item, baseHeight: height, contentWidth: width - padding * 2, chrome: chrome)
    }

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
                    ClipContentView(item: item, font: .title3, baseSize: 15, fitsImageInside: !growsToFitImage)
                } else {
                    Text("Clipboard history is empty")
                        .font(.title3)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(Self.padding)
        .frame(width: width, height: growsToFitImage ? Self.fittedHeight(for: item, width: width, height: height) : height)
        .surface(cornerRadius: 22, isSelected: isSelected)
    }
}
