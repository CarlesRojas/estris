import SwiftUI

/// The Delete to Trash settings pane: the on/off switch, then Settings and Excluded Apps tabs.
struct DeleteToTrashPane: View {
    /// What it needs, for its Permissions section and the prompt when it's turned on.
    static let permissions: [PermissionUse] = [
        PermissionUse(permission: .accessibility, reason: "Only to see the Delete key, whether you're typing, and which commands an app's menus have.", without: "Without it, Delete to Trash can't do anything."),
    ]

    private enum Tab: String, CaseIterable {
        case settings = "Settings"
        case excludedApps = "Excluded Apps"
    }

    @ObservedObject var settings: DeleteToTrashSettings
    @State private var tab = Tab.settings

    var body: some View {
        UtilityPane(
            pane: .deleteToTrash,
            summary: "Press Delete to delete what's selected, as on Windows: files in Finder, photos, notes and more.",
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
            PermissionsSection(uses: DeleteToTrashPane.permissions)
            Section {
                Toggle(isOn: $settings.usesDelete) {
                    Text("Delete (⌫)")
                    Text("The delete key on a Mac keyboard, Backspace on other keyboards.")
                }
                .resetMenu($settings.usesDelete, to: DeleteToTrashSettings.defaultUsesDelete)
                Toggle(isOn: $settings.usesForwardDelete) {
                    Text("Forward Delete (⌦)")
                    Text("The Delete key on keyboards made for Windows, or fn-Delete on a Mac keyboard.")
                }
                .resetMenu($settings.usesForwardDelete, to: DeleteToTrashSettings.defaultUsesForwardDelete)
                Toggle(isOn: $settings.shiftDeletesImmediately) {
                    Text("Shift-Delete deletes immediately")
                    Text("Without going to the Trash, where the app can, like Delete Immediately in Finder. Off, Shift-Delete is left as it is.")
                }
                .resetMenu($settings.shiftDeletesImmediately, to: DeleteToTrashSettings.defaultShiftDeletesImmediately)
            } header: {
                Text("Keys")
            } footer: {
                Text("Works in apps with a command on ⌘⌫ in their menus, like Move to Trash or Delete. While typing, Delete deletes text as usual. Holding it down deletes once. In Finder's Trash, it deletes immediately.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Reset to Defaults") { settings.reset() }
            }
        }
        .formStyle(.grouped)
        .settingsPage()
    }
}
