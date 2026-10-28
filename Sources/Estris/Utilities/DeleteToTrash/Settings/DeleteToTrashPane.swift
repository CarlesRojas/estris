import SwiftUI

/// The Delete to Trash settings pane: the on/off switch and which keys move items to the Trash.
struct DeleteToTrashPane: View {
    /// What it needs, for its Permissions section and the prompt when it's turned on.
    static let permissions: [PermissionUse] = [
        PermissionUse(permission: .accessibility, reason: "Only to see the Delete key and whether you're typing.", without: "Without it, Delete to Trash can't do anything."),
    ]

    @ObservedObject var settings: DeleteToTrashSettings

    var body: some View {
        VStack(spacing: 0) {
            UtilityHeader(
                title: SettingsPane.deleteToTrash.title,
                symbol: SettingsPane.deleteToTrash.symbol,
                summary: "Press Delete in Finder to move the selected files to the Trash, without ⌘.",
                isOn: $settings.isEnabled,
                permissions: Self.permissions
            )

            Form {
                PermissionsSection(uses: Self.permissions)
                Section {
                    Toggle(isOn: $settings.usesForwardDelete) {
                        Text("Forward Delete too")
                        Text("The ⌦ key, or fn-Delete on a laptop.")
                    }
                    .resetMenu($settings.usesForwardDelete, to: DeleteToTrashSettings.defaultUsesForwardDelete)
                } header: {
                    Text("Keys")
                } footer: {
                    Text("While renaming a file or typing in a search field, Delete deletes text as usual. Holding it down moves the files once.")
                        .foregroundStyle(.secondary)
                }
                Section {
                    Button("Reset to Defaults") { settings.reset() }
                }
            }
            .formStyle(.grouped)
            .settingsPage()
            .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
