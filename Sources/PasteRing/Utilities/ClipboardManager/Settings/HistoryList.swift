import AppKit
import SwiftUI

/// The Clipboard Manager's History tab: every saved entry, searchable, with delete and
/// Clear All.
struct HistoryPreferences: View {
    @ObservedObject var history: ClipboardHistory
    @ObservedObject var settings: ClipboardSettings
    @Environment(\.dateTimeFormat) private var dateTimeFormat
    @State private var confirmingClear = false
    @State private var search = ""

    private let mutedRed = Color.red.opacity(0.88)

    /// Entries matching the search.
    private var results: [ClipItem] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return history.items }
        return history.items.filter { $0.text.localizedCaseInsensitiveContains(query) || $0.sourceName.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        // The search stays pinned at the top; the entries scroll below, grouped like every
        // other settings page.
        VStack(spacing: 0) {
            SearchField(text: $search)
                .pinnedAboveList()

            Form {
                Section {
                    if history.items.isEmpty {
                        placeholder("No clipboard entries yet")
                    } else if results.isEmpty {
                        placeholder("No entries match \u{201C}\(search)\u{201D}")
                    } else {
                        ForEach(results) { item in
                            row(item)
                        }
                    }
                } header: {
                    HStack {
                        Text(countText)
                        Spacer()
                        Button("Clear All", role: .destructive) {
                            confirmingClear = true
                        }
                        .disabled(history.items.isEmpty)
                    }
                }
            }
            .formStyle(.grouped)
            .settingsPage()
        }
        .confirmationDialog("Delete all clipboard entries?", isPresented: $confirmingClear) {
            Button("Clear All", role: .destructive) { history.clear() }
        }
    }

    private var countText: String {
        let total = history.items.count == 1 ? String(localized: "1 entry") : String(localized: "\(history.items.count) entries")
        return search.isEmpty ? total : String(localized: "\(results.count) of \(total)")
    }

    private func placeholder(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
    }

    /// Laid out like the Default overlay card: app and date on top, the content below.
    private func row(_ item: ClipItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SourceIcon(item: item, size: 22)
                Text(item.sourceName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(dateTimeFormat.string(from: item.date))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button {
                    history.remove(item)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(mutedRed)
                .help("Delete this entry")
            }

            Group {
                if item.kind == .image {
                    ClipContentView(item: item, fitsImageInside: true, imageAlignment: .leading)
                        .frame(height: 140)
                } else {
                    ClipContentView(item: item)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }

}
