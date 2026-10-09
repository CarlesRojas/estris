import AppKit
import SwiftUI

/// Every installed app with a switch, all on until switched off, under a pinned search
/// field. Shared by utilities that let apps be left out.
struct AppSwitchList: View {
    /// Bundle identifiers of the apps switched off.
    @Binding var excluded: Set<String>
    /// Header text when nothing is switched off, such as "All apps recorded".
    let allOnText: String
    /// Apps that can't be switched on, with the reason shown under their name.
    var locked: [String: String] = [:]

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
                            row(app)
                        }
                    }
                } header: {
                    Text(excluded.isEmpty ? allOnText : "\(excluded.count) excluded")
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

    private func row(_ app: InstalledApp) -> some View {
        Toggle(isOn: isOn(app)) {
            HStack(spacing: 10) {
                AppIconView(bundleID: app.bundleID, size: 24, url: app.url)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name)
                    if let reason = locked[app.bundleID] {
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .toggleStyle(.switch)
        .disabled(locked[app.bundleID] != nil)
    }

    private func isOn(_ app: InstalledApp) -> Binding<Bool> {
        Binding(
            get: { locked[app.bundleID] == nil && !excluded.contains(app.bundleID) },
            set: { on in
                if on {
                    excluded.remove(app.bundleID)
                } else {
                    excluded.insert(app.bundleID)
                }
            }
        )
    }
}
