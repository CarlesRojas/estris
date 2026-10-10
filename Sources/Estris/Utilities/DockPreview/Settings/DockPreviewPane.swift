import SwiftUI

/// The Dock Preview settings pane: the on/off switch, the permissions it needs, and how the
/// previews look and open.
struct DockPreviewPane: View {
    /// What it needs, for its Permissions section and the prompt when it's turned on.
    static let permissions: [PermissionUse] = [
        PermissionUse(permission: .accessibility, reason: "Only to know which Dock icon is under the pointer, and to bring forward or close the window you pick.", without: "Without it, Dock Preview can't do anything."),
        PermissionUse(permission: .screenRecording, reason: "Only to show a thumbnail of what each window shows. Nothing is saved or sent.", without: "Without it, each window shows its app's icon instead of a thumbnail."),
    ]

    @ObservedObject var settings: DockPreviewSettings

    var body: some View {
        VStack(spacing: 0) {
            UtilityHeader(
                title: SettingsPane.dockPreview.title,
                symbol: SettingsPane.dockPreview.symbol,
                summary: "Rest the pointer on an app in the Dock to see its windows, and click one to open it.",
                isOn: $settings.isEnabled,
                permissions: Self.permissions
            )

            Form {
                PermissionsSection(uses: DockPreviewPane.permissions)
                Section("Previews") {
                    LabeledContent("Size") {
                        HStack(spacing: 8) {
                            Slider(value: $settings.size, in: DockPreviewSettings.sizes, step: 10)
                                .labelsHidden()
                            Text(verbatim: "\(Int(settings.size)) pt")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 56, alignment: .trailing)
                        }
                    }
                    .resetMenu($settings.size, to: DockPreviewSettings.defaultSize)
                    Picker("Open after hovering for", selection: $settings.openDelay) {
                        ForEach(HoverDelay.allCases) { delay in
                            Text(verbatim: delay.title).tag(delay)
                        }
                    }
                    .resetMenu($settings.openDelay, to: DockPreviewSettings.defaultOpenDelay)
                    Toggle("Show only windows on the current desktop", isOn: $settings.currentDesktopOnly)
                        .resetMenu($settings.currentDesktopOnly, to: DockPreviewSettings.defaultCurrentDesktopOnly)
                    Toggle("Show a button to close each window", isOn: $settings.showsCloseButton)
                        .resetMenu($settings.showsCloseButton, to: DockPreviewSettings.defaultShowsCloseButton)
                    Toggle("Switch windows with the scroll wheel", isOn: $settings.scrollSwitchesWindows)
                        .resetMenu($settings.scrollSwitchesWindows, to: DockPreviewSettings.defaultScrollSwitchesWindows)
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
