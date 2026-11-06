import SwiftUI

/// The Auto Quit settings pane: the on/off switch, then Settings and Excluded Apps tabs.
struct AutoQuitPane: View {
    /// What it needs, for its Permissions section and the prompt when it's turned on.
    static let permissions: [PermissionUse] = [
        PermissionUse(permission: .accessibility, reason: "Only to see when an app's last window closes.", without: "Without it, Auto Quit can't do anything."),
    ]

    private enum Tab: String, CaseIterable {
        case settings = "Settings"
        case excludedApps = "Excluded Apps"
    }

    @ObservedObject var settings: AutoQuitSettings
    @State private var tab = Tab.settings

    var body: some View {
        UtilityPane(
            pane: .autoQuit,
            summary: "Quits an app when you close its last window.",
            isOn: $settings.isEnabled,
            permissions: Self.permissions,
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
            PermissionsSection(uses: AutoQuitPane.permissions)
            Section {
                Picker("Quit", selection: $settings.delay) {
                    ForEach(QuitDelay.allCases) { delay in
                        Text(delay.title).tag(delay)
                    }
                }
                .resetMenu($settings.delay, to: AutoQuitSettings.defaultDelay)
            } header: {
                Text("General")
            }
            Section {
                Button("Reset to Defaults") { settings.reset() }
            }
        }
        .formStyle(.grouped)
        .settingsPage()
    }
}
