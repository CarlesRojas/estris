import SwiftUI

/// App icon and name on top, the copied text below, filling the card and truncating where
/// it ends. Used by Default and Stack.
struct EntryCard: View {
    let item: ClipItem?
    let width: CGFloat
    let height: CGFloat
    var isSelected = false
    @Environment(\.overlayActions) private var actions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let item {
                HStack(spacing: 10) {
                    AppIconView(bundleID: item.sourceBundleID, size: 28)
                    Text(AppIcons.name(for: item.sourceBundleID) ?? "Unknown app")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                // Room for the date and trash button in the corner.
                .padding(.trailing, actions.isEnabled ? ContentCard.cornerReserve : 0)
            }
            Text(item?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Clipboard history is empty")
                .font(.title3)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(20)
        .frame(width: width, height: height)
        .surface(cornerRadius: 22, isSelected: isSelected)
    }
}
