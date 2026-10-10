import SwiftUI

/// The Color Picker settings pane: the on/off switch, the shortcut and the copy format.
struct ColorPickerPane: View {
    @ObservedObject var settings: ColorPickerSettings
    /// Copies one of the recent colors.
    let copy: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            UtilityHeader(
                title: SettingsPane.colorPicker.title,
                symbol: SettingsPane.colorPicker.symbol,
                summary: "Pick a color anywhere on screen with a shortcut and copy it.",
                isOn: $settings.isEnabled
            )

            Form {
                PermissionsSection(uses: [])
                Section("Shortcut") {
                    LabeledContent("Pick a color") {
                        ShortcutRecorder(shortcut: $settings.shortcut)
                    }
                }
                Section("Copy as") {
                    Picker("Format", selection: $settings.format) {
                        ForEach(ColorFormat.allCases) { format in
                            Text(verbatim: format.title).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                    if settings.format == .hex {
                        Toggle("Include # prefix", isOn: $settings.hashPrefix)
                    }
                    LabeledContent("Example") {
                        Text(verbatim: settings.format.string(red: 1, green: 0.5, blue: 0, hashPrefix: settings.hashPrefix))
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                Section {
                    RecentColors(settings: settings, copy: copy)
                        .padding(.vertical, 2)
                } header: {
                    HStack {
                        Text("Recent Colors")
                        Spacer()
                        if !settings.recentColors.isEmpty {
                            Button("Clear") { settings.clearRecentColors() }
                                .buttonStyle(.link)
                                .font(.callout)
                        }
                    }
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
