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
                    LabeledContent("Density") {
                        slider($settings.density, in: SeasonsSettings.densityRange, step: 0.05) {
                            "\(Int((settings.density * 100).rounded()))%"
                        }
                    }
                    .resetMenu($settings.density, to: SeasonsSettings.defaultDensity)
                    LabeledContent("Wind") {
                        windSlider {
                            let percent = Int((abs(settings.wind) * 100).rounded())
                            guard percent > 0 else { return String(localized: "Calm") }
                            return settings.wind < 0 ? "← \(percent)%" : "\(percent)% →"
                        }
                    }
                    .resetMenu($settings.wind, to: SeasonsSettings.defaultWind)
                    Toggle("Falling", isOn: $settings.isFalling)
                        .resetMenu($settings.isFalling, to: true)
                } header: {
                    Text("Effect")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Automatic follows the date: snow in winter, petals in spring, sand in summer and leaves in autumn, flipped south of the equator.")
                        Text("It falls behind your windows; what you push, dig out or shake off a window comes in front until it lands.")
                    }
                    .foregroundStyle(.secondary)
                }
                Section {
                    LabeledContent("On each window") {
                        slider($settings.windowLimit, in: SeasonsSettings.windowLimitRange, step: 50) {
                            "\(Int(settings.windowLimit))"
                        }
                    }
                    .resetMenu($settings.windowLimit, to: SeasonsSettings.defaultWindowLimit)
                    LabeledContent("At the bottom") {
                        slider($settings.bottomLimit, in: SeasonsSettings.bottomLimitRange, step: 250) {
                            "\(Int(settings.bottomLimit))"
                        }
                    }
                    .resetMenu($settings.bottomLimit, to: SeasonsSettings.defaultBottomLimit)
                } header: {
                    Text("Piles")
                } footer: {
                    Text("The most that stays in a pile; past that, leaves and petals melt away and snow and sand fall off. Moving or shaking a window drops what is on it.")
                        .foregroundStyle(.secondary)
                }
                Section {
                    sizeRow("Snow", $settings.snowSize)
                    sizeRow("Petals", $settings.petalSize)
                    sizeRow("Sand", $settings.sandSize)
                    sizeRow("Leaves", $settings.leafSize)
                } header: {
                    Text("Particle Size")
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

    /// One kind of particle's size, as a share of its usual size.
    private func sizeRow(_ title: LocalizedStringKey, _ value: Binding<Double>) -> some View {
        LabeledContent(title) {
            slider(value, in: SeasonsSettings.sizeRange, step: 0.05) {
                "\(Int((value.wrappedValue * 100).rounded()))%"
            }
        }
        .resetMenu(value, to: SeasonsSettings.defaultSize)
    }

    /// The wind's slider, which fills from calm in the middle, with its value.
    private func windSlider(label: () -> String) -> some View {
        let text = label()
        return HStack {
            WindSlider(
                value: Binding(get: { settings.wind }, set: { settings.wind = abs($0) < 0.04 ? 0 : $0 }),
                range: SeasonsSettings.windRange,
                fill: .controlAccentColor
            )
            .frame(width: 200)
            Text(verbatim: text)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)
        }
    }

    private func slider(_ value: Binding<Double>, in range: ClosedRange<Double>, step: Double, label: () -> String) -> some View {
        let text = label()
        return HStack {
            Slider(value: value, in: range, step: step)
                .frame(width: 200)
            Text(verbatim: text)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)
        }
    }
}
