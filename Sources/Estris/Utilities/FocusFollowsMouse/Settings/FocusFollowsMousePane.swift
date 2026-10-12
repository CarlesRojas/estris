import SwiftUI

/// The Focus Follows Mouse settings pane: the on/off switch, then Settings and Excluded Apps
/// tabs.
struct FocusFollowsMousePane: View {
    /// What it needs, for its Permissions section and the prompt when it's turned on.
    static let permissions: [PermissionUse] = [
        PermissionUse(permission: .accessibility, reason: "Only to bring the window under the pointer to the front.", without: "Without it, Focus Follows Mouse can't do anything."),
    ]

    private enum Tab: String, CaseIterable {
        case settings = "Settings"
        case excludedApps = "Excluded Apps"
    }

    @ObservedObject var settings: FocusFollowsMouseSettings
    @State private var tab = Tab.settings

    var body: some View {
        UtilityPane(
            pane: .focusFollowsMouse,
            summary: "The window under the pointer comes to the front and gets the focus.",
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
            PermissionsSection(uses: FocusFollowsMousePane.permissions)
            Section("General") {
                Picker("Focus after hovering for", selection: $settings.delay) {
                    ForEach(HoverDelay.allCases) { delay in
                        Text(verbatim: delay.title).tag(delay)
                    }
                }
                .resetMenu($settings.delay, to: FocusFollowsMouseSettings.defaultDelay)
                LabeledContent("Skip windows when moving faster than") {
                    HStack(spacing: 8) {
                        Slider(value: $settings.passThroughSpeed, in: FocusFollowsMouseSettings.passThroughSpeeds, step: 100)
                            .labelsHidden()
                        Text(verbatim: "\(Int(settings.passThroughSpeed)) pt/s")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 72, alignment: .trailing)
                    }
                }
                .resetMenu($settings.passThroughSpeed, to: FocusFollowsMouseSettings.defaultPassThroughSpeed)
            }
            Section("Switching Apps") {
                Toggle(isOn: $settings.keepsNewAppsInFront) {
                    Text("Keep apps you open or switch to in front")
                    Text("Opened, clicked, picked with ⌘Tab or in Mission Control, they are often away from the pointer; this leaves time to get there.")
                }
                .resetMenu($settings.keepsNewAppsInFront, to: FocusFollowsMouseSettings.defaultKeepsNewAppsInFront)
                LabeledContent("Keep them in front for") {
                    HStack(spacing: 8) {
                        // No step: it would draw a tick mark for every second.
                        Slider(
                            value: Binding(get: { settings.newAppSeconds }, set: { settings.newAppSeconds = $0.rounded() }),
                            in: FocusFollowsMouseSettings.newAppSecondsRange
                        )
                            .labelsHidden()
                        Text("\(Int(settings.newAppSeconds)) s")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 72, alignment: .trailing)
                    }
                }
                .resetMenu($settings.newAppSeconds, to: FocusFollowsMouseSettings.defaultNewAppSeconds)
                .disabled(!settings.keepsNewAppsInFront)
            }
            Section {
                Button("Reset to Defaults") { settings.reset() }
            }
        }
        .formStyle(.grouped)
        .settingsPage()
    }
}
