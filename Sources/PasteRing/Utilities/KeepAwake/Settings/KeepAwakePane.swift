import SwiftUI

/// The Keep Awake settings pane: the on/off switch, how long for each power source, and what
/// it is doing now.
struct KeepAwakePane: View {
    @ObservedObject var settings: KeepAwakeSettings
    @ObservedObject var status: KeepAwakeStatus
    @Environment(\.dateTimeFormat) private var dateTimeFormat

    var body: some View {
        VStack(spacing: 0) {
            UtilityHeader(
                title: SettingsPane.keepAwake.title,
                symbol: SettingsPane.keepAwake.symbol,
                summary: "Stops your Mac and its display from going to sleep.",
                isOn: $settings.isEnabled
            )

            Form {
                Section("Keep awake for") {
                    picker("On power adapter", selection: $settings.onPower)
                    picker("On battery", selection: $settings.onBattery)
                }
                if settings.isEnabled {
                    Section("Now") {
                        LabeledContent("Power source") {
                            Text(status.isOnBattery ? String(localized: "Battery") : String(localized: "Power adapter"))
                        }
                        LabeledContent("Keeping awake") {
                            Text(stateText)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .settingsPage()
            .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func picker(_ title: LocalizedStringKey, selection: Binding<KeepAwakeDuration>) -> some View {
        Picker(title, selection: selection) {
            ForEach(KeepAwakeDuration.allCases) { duration in
                Text(duration.title).tag(duration)
            }
        }
    }

    private var stateText: String {
        switch status.state {
        case .off, .paused: String(localized: "No")
        case .indefinitely: String(localized: "Indefinitely")
        case .until(let end): String(localized: "Until \(dateTimeFormat.timeString(from: end))")
        }
    }
}
