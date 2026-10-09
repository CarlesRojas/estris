import SwiftUI

/// Cards keep their width and grow taller, down from a fixed top edge, so a copied image
/// shows whole at its own proportions.
enum ImageFitting {
    /// Tallest a card may grow to fit an image.
    static let maxCardHeight: CGFloat = 600

    /// The card height that shows `item`'s image at `contentWidth`, given the space the rest
    /// of the card takes (`chrome`). Never below `baseHeight`, never above the limit.
    @MainActor
    static func cardHeight(for item: ClipItem?, baseHeight: CGFloat, contentWidth: CGFloat, chrome: CGFloat) -> CGFloat {
        guard let item, item.kind == .image,
              let size = ClipThumbnails.image(for: item)?.size, size.width > 0
        else { return baseHeight }
        let needed = chrome + contentWidth * size.height / size.width
        return min(max(baseHeight, needed), max(baseHeight, maxCardHeight))
    }
}

/// How far a style's front card reaches below the area it was laid out in, so the position
/// pill can move down out of its way.
struct OverlayGrowthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
