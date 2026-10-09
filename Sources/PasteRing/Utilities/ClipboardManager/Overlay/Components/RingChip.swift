import SwiftUI

struct RingChip: View {
    let item: ClipItem
    let isSelected: Bool
    var width: CGFloat = 280
    var height: CGFloat = 56
    @Environment(\.overlayActions) private var actions

    var body: some View {
        HStack(spacing: 10) {
            AppIconView(bundleID: item.sourceBundleID, size: 24)
            // No line limit: the text fills the chip and truncates where it ends.
            Text(item.text.singleLine)
                .font(.body)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                // Room for the date and trash button in the corner.
                .padding(.trailing, max(0, actions.cornerReserve - 12))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        // Every chip on the ring has the same size.
        .frame(width: width, height: height)
        .surface(cornerRadius: 18, isSelected: isSelected)
    }
}
