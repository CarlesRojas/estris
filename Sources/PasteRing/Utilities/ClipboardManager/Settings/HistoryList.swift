import AppKit
import SwiftUI

/// The Clipboard Manager's History tab: every saved entry, searchable, with its quick-pick
/// key, delete and Clear All.
struct HistoryPreferences: View {
    @ObservedObject var history: ClipboardHistory
    @ObservedObject var settings: ClipboardSettings
    @Environment(\.dateTimeFormat) private var dateTimeFormat
    @State private var confirmingClear = false
    @State private var search = ""

    private let mutedRed = Color.red.opacity(0.88)

    /// Entries matching the search, with their position in the full history.
    private var results: [(position: Int, item: ClipItem)] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return history.items.enumerated()
            .map { (position: $0.offset, item: $0.element) }
            .filter { query.isEmpty || $0.item.text.localizedCaseInsensitiveContains(query) || $0.item.sourceName.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                SearchField(text: $search)
                Text(countText)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                Button("Clear All", role: .destructive) {
                    confirmingClear = true
                }
                .disabled(history.items.isEmpty)
            }
            .padding(12)

            Divider()

            if history.items.isEmpty {
                placeholder("No clipboard entries yet")
            } else if results.isEmpty {
                placeholder("No entries match \u{201C}\(search)\u{201D}")
            } else {
                List {
                    ForEach(results, id: \.item.id) { result in
                        row(result.item, position: result.position)
                    }
                }
                .listStyle(.inset)
            }
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(_ item: ClipItem, position: Int) -> some View {
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
            if let key = quickPickKey(position) {
                Text(key)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .help("Quick-pick key while the overlay is open")
            }
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

    /// The first nine entries can be pasted from the overlay with the shortcut's modifiers
    /// plus their number.
    private func quickPickKey(_ position: Int) -> String? {
        guard position < 9, let shortcut = settings.shortcuts.first else { return nil }
        return "\(shortcut.modifierSymbols)\(position + 1)"
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
