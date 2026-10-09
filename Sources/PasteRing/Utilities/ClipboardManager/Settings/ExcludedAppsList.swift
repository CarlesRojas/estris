import AppKit
import SwiftUI

/// The Clipboard Manager's Excluded Apps tab: every installed app with a switch. All are
/// on (recorded) until switched off.
struct ExcludedAppsList: View {
    @ObservedObject var settings: ClipboardSettings
    @State private var apps: [InstalledApp] = []
    @State private var isLoading = true
    @State private var search = ""

    private var results: [InstalledApp] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        // The search stays pinned at the top; the apps scroll below, grouped like every other
        // settings page.
        VStack(spacing: 0) {
            SearchField(text: $search, prompt: "Search apps")
                .pinnedAboveList()

            Form {
                Section {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    } else {
                        ForEach(results) { app in
                            Toggle(isOn: isRecorded(app)) {
                                HStack(spacing: 10) {
                                    AppIconView(bundleID: app.bundleID, size: 24, url: app.url)
                                    Text(app.name)
                                }
                            }
                            .toggleStyle(.switch)
                        }
                    }
                } header: {
                    Text(settings.excludedApps.isEmpty ? "All apps recorded" : "\(settings.excludedApps.count) excluded")
                }
            }
            .formStyle(.grouped)
            .settingsPage()
        }
        .task {
            guard apps.isEmpty else { return }
            apps = await Task.detached(priority: .userInitiated) { InstalledApps.scan() }.value
            isLoading = false
        }
    }

    private func isRecorded(_ app: InstalledApp) -> Binding<Bool> {
        Binding(
            get: { !settings.excludedApps.contains(app.bundleID) },
            set: { recorded in
                if recorded {
                    settings.excludedApps.remove(app.bundleID)
                } else {
                    settings.excludedApps.insert(app.bundleID)
                }
            }
        )
    }
}
