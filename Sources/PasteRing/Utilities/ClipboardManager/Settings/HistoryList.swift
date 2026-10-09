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
        let total = history.items.count == 1 ? "1 entry" : "\(history.items.count) entries"
        return search.isEmpty ? total : "\(results.count) of \(total)"
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
    }

    private func row(_ item: ClipItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            SourceIcon(item: item, size: 28)
            VStack(alignment: .leading, spacing: 4) {
                ClipContentView(item: item, singleLine: true)
                    .lineLimit(2)
                    .frame(maxHeight: item.kind == .image ? 56 : nil, alignment: .leading)
                Text("\(item.sourceName) · \(dateTimeFormat.string(from: item.date))")
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

/// A native search field.
struct SearchField: NSViewRepresentable {
    @Binding var text: String
    var prompt = "Search"

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = prompt
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        if field.stringValue != text {
            field.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}
