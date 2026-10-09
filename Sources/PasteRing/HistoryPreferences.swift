import AppKit
import SwiftUI

/// The Clipboard Manager's History tab: every saved entry, with delete and Clear All.
struct HistoryPreferences: View {
    @ObservedObject var history: ClipboardHistory
    @Environment(\.dateTimeFormat) private var dateTimeFormat
    @State private var confirmingClear = false

    private let mutedRed = Color.red.opacity(0.88)

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(history.items.count == 1 ? "1 entry" : "\(history.items.count) entries")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear All", role: .destructive) {
                    confirmingClear = true
                }
                .disabled(history.items.isEmpty)
            }
            .padding(12)

            Divider()

            if history.items.isEmpty {
                Text("No clipboard entries yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(history.items) { item in
                        HStack(alignment: .top, spacing: 12) {
                            AppIconView(bundleID: item.sourceBundleID, size: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.text.singleLine)
                                    .lineLimit(2)
                                    .truncationMode(.tail)
                                Text(dateTimeFormat.string(from: item.date))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                history.remove(item)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(mutedRed)
                            .help("Delete this entry")
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.inset)
            }
        }
        .confirmationDialog("Delete all clipboard entries?", isPresented: $confirmingClear) {
            Button("Clear All", role: .destructive) { history.clear() }
        }
    }
}
