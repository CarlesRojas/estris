import SwiftUI

/// The Auto Quit settings pane: the on/off switch, then Settings and Excluded Apps tabs.
struct AutoQuitPane: View {
    private enum Tab: String, CaseIterable {
        case settings = "Settings"
        case excludedApps = "Excluded Apps"
    }

    @ObservedObject var settings: AutoQuitSettings
    @ObservedObject var activity: AutoQuitActivity
    @Environment(\.dateTimeFormat) private var dateTimeFormat
    @State private var tab = Tab.settings

    var body: some View {
        UtilityPane(
            pane: .autoQuit,
            summary: "Quits an app when you close its last window.",
            isOn: $settings.isEnabled,
            tab: $tab
        ) { tab in
            switch tab {
            case .settings:
                form
            case .excludedApps:
                AppSwitchList(excluded: $settings.excludedApps, locked: AutoQuitSettings.alwaysKept)
            }
        }
    }

    private var form: some View {
        Form {
            Section {
                Picker("Quit", selection: $settings.delay) {
                    ForEach(QuitDelay.allCases) { delay in
                        Text(delay.title).tag(delay)
                    }
                }
            } header: {
                Text("General")
            } footer: {
                Text("Apps opened without a window, and apps that live in the menu bar, are left alone. The Finder is never quit. Needs Accessibility access to see each app's windows.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                if activity.entries.isEmpty {
                    Text(settings.isEnabled ? "Nothing yet. Close an app's last window to see what happens." : "Turn Auto Quit on to start.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(activity.entries) { entry in
                        HStack(alignment: .firstTextBaseline) {
                            Text(entry.message)
                            Spacer()
                            Text(dateTimeFormat.timeString(from: entry.date))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Recent Activity")
                    Spacer()
                    Button("Clear") { activity.clear() }
                        .disabled(activity.entries.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .settingsPage()
    }
}
