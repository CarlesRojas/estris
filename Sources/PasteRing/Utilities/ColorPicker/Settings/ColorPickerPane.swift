import SwiftUI

/// The Color Picker settings pane: the on/off switch, the shortcut and the copy format.
struct ColorPickerPane: View {
    @ObservedObject var settings: ColorPickerSettings
    @State private var screenRecordingAllowed = ScreenSampler.isAllowed
    private static let screenRecordingSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!

    var body: some View {
        VStack(spacing: 0) {
            UtilityHeader(
                title: SettingsPane.colorPicker.title,
                symbol: SettingsPane.colorPicker.symbol,
                summary: "Pick a color anywhere on screen with a shortcut and copy it.",
                isOn: $settings.isEnabled
            )

            Form {
                if !screenRecordingAllowed {
                    Section {
                        LabeledContent {
                            Button("Open Screen Recording Settings") {
                                ScreenSampler.requestAccess()
                                NSWorkspace.shared.open(Self.screenRecordingSettingsURL)
                            }
                        } label: {
                            Text("Screen Recording")
                            Text("Allow it, then relaunch PasteRing, to see the color's value while picking.")
                        }
                    }
                }
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
                    Button("Reset to Defaults") { settings.reset() }
                }
            }
            .formStyle(.grouped)
            .settingsPage()
            .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { screenRecordingAllowed = ScreenSampler.isAllowed }
    }
}
