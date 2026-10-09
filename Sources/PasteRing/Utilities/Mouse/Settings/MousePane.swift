import SwiftUI

/// The Mouse settings pane: the middle click gesture.
struct MousePane: View {
    @ObservedObject var settings: MouseSettings

    var body: some View {
        VStack(spacing: 0) {
            UtilityHeader(title: SettingsPane.mouse.title, symbol: SettingsPane.mouse.symbol, summary: "Middle click from the trackpad.")

            Form {
                Section {
                    Picker("Middle click", selection: $settings.middleClick) {
                        ForEach(MiddleClickGesture.allCases) { gesture in
                            Text(gesture.title).tag(gesture)
                        }
                    }
                } header: {
                    Text("Trackpad")
                } footer: {
                    Text("A quick tap with the fingers held still clicks the middle button where the pointer is, for example to open a link in a new tab. If Look Up is set to a three-finger tap in System Settings > Trackpad, turn it off to use three fingers here. Needs Accessibility access.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .settingsPage()
            .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
