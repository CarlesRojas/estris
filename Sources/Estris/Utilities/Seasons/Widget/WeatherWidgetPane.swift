import SwiftUI

/// The Weather Widget pane: whether the widget shows, which controls it has, and where it
/// sits.
struct WeatherWidgetPane: View {
    @ObservedObject var settings: WeatherWidgetSettings
    @ObservedObject var seasons: SeasonsSettings
    let resetPosition: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            UtilityHeader(
                title: SettingsPane.weatherWidget.title,
                symbol: SettingsPane.weatherWidget.symbol,
                summary: "A small panel on your desktop to start and stop the falling and change the wind and how much falls.",
                isOn: $settings.isShown
            )

            Form {
                if !seasons.isEnabled {
                    Section {
                        WarningLabel("Shows while Seasons is on.")
                    }
                }
                Section {
                    Toggle("Season", isOn: $settings.showsSeason)
                        .resetMenu($settings.showsSeason, to: WeatherWidgetSettings.Default.showsSeason)
                    Toggle("Intensity", isOn: $settings.showsIntensity)
                        .resetMenu($settings.showsIntensity, to: WeatherWidgetSettings.Default.showsIntensity)
                    Toggle("Wind", isOn: $settings.showsWind)
                        .resetMenu($settings.showsWind, to: WeatherWidgetSettings.Default.showsWind)
                } header: {
                    Text("Controls")
                } footer: {
                    Text("The button to start and stop the falling is always there. What you change on the widget is kept when Estris quits.")
                        .foregroundStyle(.secondary)
                }
                Section("Placement") {
                    Picker("Sits", selection: $settings.placement) {
                        ForEach(WidgetPlacement.allCases) { placement in
                            Text(placement.title).tag(placement)
                        }
                    }
                    .resetMenu($settings.placement, to: WeatherWidgetSettings.Default.placement)
                    Toggle("Snow and the rest pile up on it", isOn: $settings.collectsWeather)
                        .resetMenu($settings.collectsWeather, to: WeatherWidgetSettings.Default.collectsWeather)
                    LabeledContent("Position") {
                        Button("Move Back to the Corner", action: resetPosition)
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
