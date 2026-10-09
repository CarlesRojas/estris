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
        guard !query.isEmpty else { return log.entries }
        return log.entries.filter {
            $0.message.localizedCaseInsensitiveContains(query) || $0.source.localizedCaseInsensitiveContains(query)
        }
    }

    private var logs: some View {
        VStack(spacing: 0) {
            SearchField(text: $search, prompt: "Search logs")
                .pinnedAboveList()

            Form {
                Section {
                    if results.isEmpty {
                        Text(log.entries.isEmpty ? "Nothing logged yet." : "No entries match \u{201C}\(search)\u{201D}")
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
                                    Text(dateTimeFormat.timeString(from: entry.date))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                Text(entry.message)
                                    .textSelection(.enabled)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } header: {
                    HStack {
                        Text(log.entries.count == 1 ? "1 entry" : "\(log.entries.count) entries")
                        Spacer()
                        Button("Copy All") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(log.text, forType: .string)
                        }
                        .disabled(log.entries.isEmpty)
                        Button("Clear") { log.clear() }
                            .disabled(log.entries.isEmpty)
                    }
                }
            }
            .formStyle(.grouped)
            .settingsPage()
        }
    }

    private var settings: some View {
        Form {
            Section {
                LabeledContent("Accessibility") {
                    Text(AXIsProcessTrusted() ? "Granted" : "Not granted")
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
