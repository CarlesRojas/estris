import SwiftUI

/// The Middle Click settings pane: the on/off switch, then how many fingers tap.
struct MiddleClickPane: View {
    @ObservedObject var settings: MiddleClickSettings

    var body: some View {
        VStack(spacing: 0) {
            UtilityHeader(
                title: SettingsPane.middleClick.title,
                symbol: SettingsPane.middleClick.symbol,
                summary: "Tap the trackpad with three or four fingers to middle click.",
                isOn: $settings.isEnabled
            )

            Form {
                Section {
                    Picker("Tap with", selection: $settings.fingers) {
                        ForEach(TapFingers.allCases) { fingers in
                            Text(fingers.title).tag(fingers)
                        }
                    }
                } header: {
                    Text("General")
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
