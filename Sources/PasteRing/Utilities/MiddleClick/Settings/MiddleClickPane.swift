import SwiftUI

/// The Middle Click settings pane: the on/off switch, then Settings and Excluded Apps tabs.
struct MiddleClickPane: View {
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
            Section {
                Picker("Tap with", selection: $settings.fingers) {
                    ForEach(TapFingers.allCases) { fingers in
                        Text(fingers.title).tag(fingers)
                    }
                }
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
