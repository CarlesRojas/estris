import SwiftUI

/// The Seasons settings pane: the on/off switch, the season, where it falls, how much, how
/// much piles up, and when it pauses.
struct SeasonsPane: View {
    @ObservedObject var settings: SeasonsSettings

    var body: some View {
        VStack(spacing: 0) {
            UtilityHeader(
                title: SettingsPane.seasons.title,
                symbol: SettingsPane.seasons.symbol,
                summary: "Snow, petals, sand or leaves fall over your screens and pile up on windows.",
                isOn: $settings.isEnabled
            )

            Form {
                Section {
                    Picker("Season", selection: $settings.season) {
                        ForEach(SeasonChoice.allCases) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }
                    .resetMenu($settings.season, to: SeasonsSettings.defaultSeason)
                    Picker("Falls", selection: $settings.layer) {
                        ForEach(SeasonsLayer.allCases) { layer in
                            Text(layer.title).tag(layer)
                        }
                    }
                    .resetMenu($settings.layer, to: SeasonsSettings.defaultLayer)
                    LabeledContent("Amount") {
                        slider($settings.amount, in: SeasonsSettings.amountRange, step: 0.25) {
                            "\(Int((settings.amount * 100).rounded()))%"
                        }
                    }
                    .resetMenu($settings.amount, to: SeasonsSettings.defaultAmount)
                } header: {
                    Text("Effect")
                } footer: {
                    Text("Automatic follows the date: snow in winter, petals in spring, sand in summer and leaves in autumn, flipped south of the equator.")
                        .foregroundStyle(.secondary)
                }
                Section {
                    LabeledContent("On each window") {
                        slider($settings.windowLimit, in: SeasonsSettings.windowLimitRange, step: 10) {
                            "\(Int(settings.windowLimit))"
                        }
                    }
                    .resetMenu($settings.windowLimit, to: SeasonsSettings.defaultWindowLimit)
                    LabeledContent("At the bottom") {
                        slider($settings.bottomLimit, in: SeasonsSettings.bottomLimitRange, step: 50) {
                            "\(Int(settings.bottomLimit))"
                        }
                    }
                    .resetMenu($settings.bottomLimit, to: SeasonsSettings.defaultBottomLimit)
                } header: {
                    Text("Piles")
                } footer: {
                    Text("The most that stays in a pile; past that, the oldest melts away. Moving or shaking a window drops what is on it.")
                        .foregroundStyle(.secondary)
                }
                Section("Pause") {
                    Toggle("On battery or in Low Power Mode", isOn: $settings.pausesOnBattery)
                        .resetMenu($settings.pausesOnBattery, to: SeasonsSettings.defaultPausesOnBattery)
                    Toggle("On a screen showing a full screen app", isOn: $settings.pausesInFullScreen)
                        .resetMenu($settings.pausesInFullScreen, to: SeasonsSettings.defaultPausesInFullScreen)
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

    private func slider(_ value: Binding<Double>, in range: ClosedRange<Double>, step: Double, label: () -> String) -> some View {
        let text = label()
        return HStack {
            Slider(value: value, in: range, step: step)
                .frame(width: 200)
            Text(verbatim: text)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
    }
}
