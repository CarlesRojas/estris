import SwiftUI

/// The default style: one fixed card showing what will be pasted. Cycling swaps the
/// content, nothing moves.
struct SimpleView: View {
    @ObservedObject var state: OverlayState
    @ObservedObject var settings: AppSettings

    var body: some View {
        let item = state.selectedItem
        VStack(alignment: .leading, spacing: 12) {
            if let item {
                HStack(spacing: 10) {
                    AppIconView(bundleID: item.sourceBundleID, size: 28)
                    Text(AppIcons.name(for: item.sourceBundleID) ?? "Unknown app")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.trailing, 24)
            }
            // No line limit: the text fills the card and truncates where the card ends.
            Text(item?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Clipboard history is empty")
                .font(.title3)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(20)
        .frame(width: settings.simpleWidth, height: settings.simpleHeight)
        .surface(cornerRadius: 22)
        .modifier(OptionalClipActions(item: item))
        .transaction { $0.animation = nil }
    }
}

private struct OptionalClipActions: ViewModifier {
    let item: ClipItem?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let item {
            content.clipActions(item, trashInset: 22)
        } else {
            content
        }
    }
}
