import SwiftUI

/// The Menu Bar pane: which icon PasteRing shows in the menu bar, all in view to click, and
/// what its menu shows.
struct MenuBarPane: View {
    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 16)

    @ObservedObject var settings: MenuBarSettings

    var body: some View {
        VStack(spacing: 0) {
            UtilityHeader(
                title: SettingsPane.menuBar.title,
                symbol: SettingsPane.menuBar.symbol,
                summary: "Choose the icon PasteRing shows in the menu bar."
            )

            Form {
                Section("Icon") {
                    LazyVGrid(columns: Self.columns, spacing: 4) {
                        ForEach(MenuBarIcon.all, id: \.self) { icon in
                            iconButton(icon)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("Volume Mixer") {
                    Toggle("Show System", isOn: $settings.showsSystem)
                    Toggle("Show Apps", isOn: $settings.showsApps)
                    Toggle("Show device pickers", isOn: $settings.showsDevices)
                    Toggle("Show volume percentages", isOn: $settings.showsPercentages)
                }
                Section("Clipboard") {
                    Toggle("Show recent entries", isOn: $settings.showsClipboardHistory)
                    Stepper(value: $settings.clipboardEntries, in: 1...MenuBarSettings.maxClipboardEntries) {
                        LabeledContent("Entries") {
                            Text(verbatim: "\(settings.clipboardEntries)")
                                .monospacedDigit()
                        }
                    }
                    .disabled(!settings.showsClipboardHistory)
                    Toggle("Show Clear History button", isOn: $settings.showsClearHistory)
                }
                Section("Color Picker") {
                    Toggle("Show Pick a Color button", isOn: $settings.showsColorPicker)
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

    private func iconButton(_ icon: String) -> some View {
        let isSelected = settings.icon == icon
        return Button {
            settings.icon = icon
        } label: {
            Image(systemName: MenuBarIcon.symbol(for: icon))
                .font(.system(size: 14))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .frame(maxWidth: .infinity, minHeight: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
