import SwiftUI

/// The Keep Awake settings pane: the on/off switch, how long for each power source, and what
/// it is doing now.
struct KeepAwakePane: View {
    @ObservedObject var settings: KeepAwakeSettings
    @ObservedObject var status: KeepAwakeStatus

    var body: some View {
        VStack(spacing: 0) {
            UtilityHeader(
                title: SettingsPane.keepAwake.title,
                symbol: SettingsPane.keepAwake.symbol,
                summary: "Stops your Mac and its display from going to sleep.",
                isOn: $settings.isEnabled
            )

            Form {
                Section("Sleep after being idle for") {
                    picker("On power adapter", selection: $settings.onPower)
                    picker("On battery", selection: $settings.onBattery)
                }
                if settings.isEnabled {
                    Section("Status") {
                        LabeledContent("Power source") {
                            Text(status.isOnBattery ? String(localized: "Battery") : String(localized: "Power adapter"))
                        }
                        LabeledContent("State") {
                            Text(stateText)
                        }
                        if status.remaining != nil {
                            // Ticks while the pane is open.
                            TimelineView(.periodic(from: .now, by: 1)) { _ in
                                LabeledContent("Sleeps in") {
                                    Text(Self.countdown(status.remaining ?? 0))
                                        .monospacedDigit()
                                }
                            }
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
        case .off, .paused: String(localized: "Not keeping awake")
        case .indefinitely: String(localized: "Always on")
        case .active: status.otherAppKeepsDisplayOn ? String(localized: "Active, an app keeps the display on") : String(localized: "Active")
        case .idle: String(localized: "Inactive, macOS sleep settings apply")
        }
    }

    /// "4:05" or "1:04:05".
    private static func countdown(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        let hours = total / 3600
        let minutes = total / 60 % 60
        let rest = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
    }
}
