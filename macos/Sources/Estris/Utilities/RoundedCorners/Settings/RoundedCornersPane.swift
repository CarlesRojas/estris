import SwiftUI

/// The Rounded Corners settings pane: the on/off switch and how round the corners are.
struct RoundedCornersPane: View {
    @ObservedObject var settings: RoundedCornersSettings

    var body: some View {
        VStack(spacing: 0) {
            UtilityHeader(
                title: SettingsPane.roundedCorners.title,
                symbol: SettingsPane.roundedCorners.symbol,
                summary: "Rounds the corners of your screens by painting them black.",
                isOn: $settings.isEnabled
            )

            Form {
                Section {
                    LabeledContent("Radius") {
                        HStack {
                            Slider(value: $settings.radius, in: RoundedCornersSettings.radiusRange, step: 1)
                                .frame(width: 200)
                            Text("\(Int(settings.radius.rounded())) pt")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                    .resetMenu($settings.radius, to: RoundedCornersSettings.defaultRadius)
                } header: {
                    Text("Corners")
                } footer: {
                    Text("By default, as round as the corners of macOS windows, so a window filling the screen fits them.")
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
