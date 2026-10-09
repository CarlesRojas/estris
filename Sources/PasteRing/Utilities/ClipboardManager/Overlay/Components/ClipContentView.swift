import SwiftUI

extension ClipItem {
    /// Where the entry came from: the app, or another device for Universal Clipboard.
    @MainActor
    var sourceName: String {
        if isFromOtherDevice == true { return "Another device" }
        return AppIcons.name(for: sourceBundleID) ?? "Unknown app"
    }
}

/// The source app's icon, or a devices symbol for entries from another device.
struct SourceIcon: View {
    let item: ClipItem
    let size: CGFloat

    var body: some View {
        if item.isFromOtherDevice == true {
            Image(systemName: "laptopcomputer.and.iphone")
                .resizable()
                .scaledToFit()
                .padding(size * 0.12)
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
        } else {
            AppIconView(bundleID: item.sourceBundleID, size: size)
        }
    }
}

/// An entry's content: its text (styled, for rich text), the copied image, or the copied
/// file names.
struct ClipContentView: View {
    let item: ClipItem
    var font: Font = .body
    /// Point size of `font`, which rich text is scaled to.
    var baseSize: CGFloat = 13
    /// One line with line breaks shown as ⏎, for small rows and chips.
    var singleLine = false
    /// Show an image whole inside the space it gets, instead of at full width (for cards
    /// that keep a fixed height).
    var fitsImageInside = false
    /// Where a fitted image sits in its space.
    var imageAlignment: Alignment = .center

    var body: some View {
        switch item.kind {
        case .image:
            if let image = ClipThumbnails.image(for: item) {
                if singleLine || fitsImageInside {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: singleLine ? 4 : 8, style: .continuous))
                        // Centred in the space it gets; chips keep it next to the app icon.
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: singleLine ? .leading : imageAlignment)
                } else {
                    // The full width of the card at the image's own aspect ratio; anything
                    // taller than the card is cut off at the bottom.
                    GeometryReader { proxy in
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: proxy.size.width)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .clipped()
                }
            } else {
                label(item.text, symbol: "photo")
            }
        case .files:
            label(singleLine ? item.text.singleLine : item.text, symbol: item.text.contains("\n") ? "doc.on.doc" : "doc")
        case .richText:
            if let attributed = RichTextRenderer.attributed(for: item, baseSize: baseSize, singleLine: singleLine) {
                Text(attributed)
                    .truncationMode(.tail)
            } else {
                plainText
            }
        case .text:
            plainText
        }
    }

    private var plainText: some View {
        Text(singleLine ? item.text.singleLine : item.text.trimmingCharacters(in: .whitespacesAndNewlines))
            .font(font)
            .truncationMode(.tail)
    }

    private func label(_ text: String, symbol: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
            Text(text)
                .truncationMode(.tail)
        }
        .font(font)
    }
}
