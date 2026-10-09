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
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                SearchField(text: $search, prompt: "Search apps")
                Text(settings.excludedApps.isEmpty ? "All apps recorded" : "\(settings.excludedApps.count) excluded")
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            .padding(12)

            Divider()

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(results) { app in
                    Toggle(isOn: isRecorded(app)) {
                        HStack(spacing: 10) {
                            AppIconView(bundleID: app.bundleID, size: 24)
                            Text(app.name)
                        }
                    }
                    .toggleStyle(.switch)
                }
                .listStyle(.inset)
            }
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
