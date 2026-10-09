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

/// An entry's content: its text, an image thumbnail, or the copied file names.
struct ClipContentView: View {
    let item: ClipItem
    var font: Font = .body
    /// One line with line breaks shown as ⏎, for small rows and chips.
    var singleLine = false

    var body: some View {
        switch item.kind {
        case .image:
            if let image = ClipThumbnails.image(for: item) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                label(item.text, symbol: "photo")
            }
        case .files:
            label(singleLine ? item.text.singleLine : item.text, symbol: item.text.contains("\n") ? "doc.on.doc" : "doc")
        case .text, .richText:
            Text(singleLine ? item.text.singleLine : item.text.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(font)
                .truncationMode(.tail)
        }
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
