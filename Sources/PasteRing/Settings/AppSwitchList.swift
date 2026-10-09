import AppKit
import SwiftUI

/// Every installed app with a switch that excludes it, all off by default, under a pinned
/// search field. Shared by utilities that let apps be left out.
struct AppSwitchList: View {
    /// Bundle identifiers of the apps switched on, that is, excluded.
    @Binding var excluded: Set<String>
    /// Apps that are always excluded, with the reason shown under their name.
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
                    Text(excluded.isEmpty ? String(localized: "No apps excluded") : (excluded.count == 1 ? String(localized: "1 app excluded") : String(localized: "\(excluded.count) apps excluded")))
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
        Toggle(isOn: isExcluded(app)) {
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

    private func isExcluded(_ app: InstalledApp) -> Binding<Bool> {
        Binding(
            get: { locked[app.bundleID] != nil || excluded.contains(app.bundleID) },
            set: { isExcluded in
                if isExcluded {
                    excluded.insert(app.bundleID)
                } else {
                    excluded.remove(app.bundleID)
                }
            }
        )
    }
}
