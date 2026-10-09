import SwiftUI

struct RingChip: View {
    let item: ClipItem
    let isSelected: Bool
    var width: CGFloat = 280
    var height: CGFloat = 56
    @Environment(\.overlayActions) private var actions

    private static let horizontalPadding: CGFloat = 14
    private static let verticalPadding: CGFloat = 10
    /// Tallest a chip grows to show an image, as a multiple of the normal height.
    private static let maxImageGrowth: CGFloat = 3

    /// `height`, or taller for an image so it shows whole beside the app icon.
    static func fittedHeight(for item: ClipItem, width: CGFloat, height: CGFloat, cornerReserve: CGFloat) -> CGFloat {
        let imageWidth = width - horizontalPadding * 2 - 34 - max(0, cornerReserve - 12)
        return ImageFitting.cardHeight(
            for: item,
            baseHeight: height,
            contentWidth: imageWidth,
            chrome: verticalPadding * 2,
            maxHeight: height * maxImageGrowth
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            SourceIcon(item: item, size: 24)
            // No line limit: the text fills the chip and truncates where it ends. Images use
            // the chip's full width; the chip is made taller for them.
            ClipContentView(item: item, singleLine: item.kind != .image)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                // Room for the date and trash button in the corner.
                .padding(.trailing, max(0, actions.cornerReserve - 12))
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.vertical, Self.verticalPadding)
        .frame(width: width, height: Self.fittedHeight(for: item, width: width, height: height, cornerReserve: actions.cornerReserve))
        .surface(cornerRadius: 18, isSelected: isSelected)
    }
}
