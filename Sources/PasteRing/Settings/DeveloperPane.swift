import AppKit
import ApplicationServices
import SwiftUI

/// Hidden pane for diagnosing PasteRing, unlocked from the version in General > About:
/// the log of what the utilities did, and settings regular users don't need.
struct DeveloperPane: View {
    private enum Tab: String, CaseIterable {
        case logs = "Logs"
        case settings = "Settings"
    }

    @ObservedObject var general: GeneralSettings
    @ObservedObject var log: AppLog
    @Environment(\.dateTimeFormat) private var dateTimeFormat
    @State private var tab = Tab.logs
    @State private var search = ""
    /// Only this utility's entries; nil shows every one.
    @State private var source: String?
    /// The entry just copied with a click, marked for a moment.
    @State private var copied: UUID?

    var body: some View {
        UtilityPane(
            pane: .developer,
            summary: "Logs and settings for finding out what PasteRing is doing.",
            tab: $tab
        ) { tab in
            switch tab {
            case .logs: logs
            case .settings: settings
            }
        }
    }

    private var results: [AppLog.Entry] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return log.entries.filter { entry in
            (source == nil || entry.source == source)
                && (query.isEmpty || entry.message.localizedCaseInsensitiveContains(query) || entry.source.localizedCaseInsensitiveContains(query))
        }
    }

    /// The utilities that logged something, alphabetically.
    private var sources: [String] {
        Set(log.entries.map(\.source)).sorted()
    }

    private var logs: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                SearchField(text: $search, prompt: "Search logs")
                Picker("Utility", selection: $source) {
                    Text("All Utilities").tag(String?.none)
                    ForEach(sources, id: \.self) { source in
                        Text(verbatim: source).tag(Optional(source))
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            .pinnedAboveList()

            Form {
                Section {
                    if results.isEmpty {
                        Text(log.entries.isEmpty ? String(localized: "Nothing logged yet.") : search.isEmpty ? String(localized: "No entries from this utility.") : String(localized: "No entries match \u{201C}\(search)\u{201D}"))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    } else {
                        ForEach(results) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(entry.source)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    if copied == entry.id {
                                        Label("Copied", systemImage: "checkmark")
                                            .font(.caption)
                                            .foregroundStyle(.green)
                                    } else {
                                        Text(dateTimeFormat.timeString(from: entry.date))
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Text(entry.message)
                            }
                            .padding(.vertical, 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            // A click copies the line, as Copy All writes it.
                            .onTapGesture { copy(entry) }
                        }
                    }
                } header: {
                    HStack {
                        Text(results.count == 1 ? String(localized: "1 entry") : String(localized: "\(results.count) entries"))
                        Spacer()
                        Button("Copy All") {
                            NSPasteboard.general.clearContents()
                            // What is shown: the chosen utility and search.
                            NSPasteboard.general.setString(AppLog.text(of: results), forType: .string)
                        }
                        .disabled(results.isEmpty)
                        Button("Clear") { log.clear() }
                            .disabled(log.entries.isEmpty)
                    }
                }
            }
            .formStyle(.grouped)
            .settingsPage()
        }
    }

    private func copy(_ entry: AppLog.Entry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(AppLog.text(of: [entry]), forType: .string)
        copied = entry.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if copied == entry.id { copied = nil }
        }
    }

    private var settings: some View {
        Form {
            Section {
                LabeledContent("Accessibility") {
                    Text(AXIsProcessTrusted() ? String(localized: "Granted") : String(localized: "Not granted"))
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Status")
            }

            Section {
                Button("Hide Developer Settings") {
                    general.showsDeveloperSettings = false
                }
            }
        }
        .formStyle(.grouped)
        .settingsPage()
    }
}
