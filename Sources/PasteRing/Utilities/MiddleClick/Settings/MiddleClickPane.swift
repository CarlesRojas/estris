import SwiftUI

/// The Middle Click settings pane: the on/off switch, then Settings and Excluded Apps tabs.
struct MiddleClickPane: View {
    /// What it needs, for its Permissions section and the prompt when it's turned on.
    static let permissions: [PermissionUse] = [
        PermissionUse(permission: .accessibility, reason: "Only to send the middle click.", without: "Without it, Middle Click can't do anything."),
    ]

    private enum Tab: String, CaseIterable {
        case settings = "Settings"
        case excludedApps = "Excluded Apps"
    }

    @ObservedObject var settings: MiddleClickSettings
    @State private var tab = Tab.settings

    var body: some View {
        UtilityPane(
            pane: .middleClick,
            summary: "Tap the trackpad with three or four fingers to middle click.",
            isOn: $settings.isEnabled,
            permissions: Self.permissions,
            tab: $tab
        ) { tab in
            switch tab {
            case .settings:
                form
            case .excludedApps:
                AppSwitchList(excluded: $settings.excludedApps)
            }
        }
    }

    private var form: some View {
        Form {
            PermissionsSection(uses: MiddleClickPane.permissions)
            Section {
                Picker("Tap with", selection: $settings.fingers) {
                    ForEach(TapFingers.allCases) { fingers in
                        Text(fingers.title).tag(fingers)
                    }
                }
                .resetMenu($settings.fingers, to: MiddleClickSettings.defaultFingers)
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
