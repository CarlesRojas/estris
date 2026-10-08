import SwiftUI

/// One fixed rectangle showing what will be pasted. Cycling swaps the text, nothing moves.
struct SimpleView: View {
    @ObservedObject var state: OverlayState

    var body: some View {
        let item = state.selectedItem
        HStack(alignment: .top, spacing: 14) {
            if let item {
                AppIconView(bundleID: item.sourceBundleID, size: 32)
            }
            Text(item?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Clipboard history is empty")
                .font(.title3)
                .lineLimit(7)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(20)
        .frame(width: 560, height: 200)
        .surface(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .transaction { $0.animation = nil }
    }
}
