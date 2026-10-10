import AppKit
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
                    .resetMenu($settings.icon, to: MenuBarSettings.Default.icon)
                    Toggle("Custom color", isOn: hasCustomColor)
                        .resetMenu($settings.iconColor, to: MenuBarSettings.Default.iconColor)
                    if settings.iconColor != nil {
                        ColorPicker("Color", selection: customColor, supportsOpacity: false)
                            .resetMenu($settings.iconColor, to: MenuBarSettings.Default.iconColor)
                    }
                }
                Section("Volume Mixer") {
                    Toggle("Show System Volume", isOn: $settings.showsSystem)
                        .resetMenu($settings.showsSystem, to: MenuBarSettings.Default.showsSystem)
                    Group {
                        Toggle("Show Output", isOn: $settings.showsOutput)
                            .resetMenu($settings.showsOutput, to: MenuBarSettings.Default.showsOutput)
                        Toggle("Show Microphone", isOn: $settings.showsInput)
                            .resetMenu($settings.showsInput, to: MenuBarSettings.Default.showsInput)
                    }
                    .padding(.leading, 16)
                    .disabled(!settings.showsSystem)
                    Toggle("Show Apps Volume", isOn: $settings.showsApps)
                        .resetMenu($settings.showsApps, to: MenuBarSettings.Default.showsApps)
                    Toggle("Show device pickers", isOn: $settings.showsDevices)
                        .resetMenu($settings.showsDevices, to: MenuBarSettings.Default.showsDevices)
                    Toggle("Show volume percentages", isOn: $settings.showsPercentages)
                        .resetMenu($settings.showsPercentages, to: MenuBarSettings.Default.showsPercentages)
                }
                Section("Clipboard") {
                    Toggle("Show recent entries", isOn: $settings.showsClipboardHistory)
                        .resetMenu($settings.showsClipboardHistory, to: MenuBarSettings.Default.showsClipboardHistory)
                    Stepper(value: $settings.clipboardEntries, in: 1...MenuBarSettings.maxClipboardEntries) {
                        LabeledContent("Entries") {
                            Text(verbatim: "\(settings.clipboardEntries)")
                                .monospacedDigit()
                        }
                    }
                    .resetMenu($settings.clipboardEntries, to: MenuBarSettings.defaultClipboardEntries)
                    .disabled(!settings.showsClipboardHistory)
                    Toggle("Show Clear History button", isOn: $settings.showsClearHistory)
                        .resetMenu($settings.showsClearHistory, to: MenuBarSettings.Default.showsClearHistory)
                }
                Section("Color Picker") {
                    Toggle("Show Pick a Color button", isOn: $settings.showsColorPicker)
                        .resetMenu($settings.showsColorPicker, to: MenuBarSettings.Default.showsColorPicker)
                    Toggle("Show recent colors", isOn: $settings.showsRecentColors)
                        .resetMenu($settings.showsRecentColors, to: MenuBarSettings.Default.showsRecentColors)
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

    /// Off draws the icon in the menu bar's own colour; on starts from white.
    private var hasCustomColor: Binding<Bool> {
        Binding(
            get: { settings.iconColor != nil },
            set: { settings.iconColor = $0 ? "FFFFFF" : nil }
        )
    }

    private var customColor: Binding<Color> {
        Binding(
            get: { Color(nsColor: settings.iconColor.flatMap(NSColor.init(hex:)) ?? .white) },
            set: { settings.iconColor = ColorFormat.hex.string(for: NSColor($0), hashPrefix: false) }
        )
    }

    private func iconButton(_ icon: String) -> some View {
        let isSelected = settings.icon == icon
        return Button {
            settings.icon = icon
        } label: {
            Image(systemName: MenuBarIcon.symbol(for: icon))
                .font(.system(size: 14))
                .foregroundStyle(isSelected ? Color.white : settings.iconColor.flatMap(NSColor.init(hex:)).map { Color(nsColor: $0) } ?? Color.primary)
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
