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
                Section("Idle Time Before Sleep") {
                    picker("On power adapter", selection: $settings.onPower)
                        .resetMenu($settings.onPower, to: KeepAwakeSettings.defaultOnPower)
                    picker("On battery", selection: $settings.onBattery)
                        .resetMenu($settings.onBattery, to: KeepAwakeSettings.defaultOnBattery)
                    Toggle("Start the screen saver instead of sleeping", isOn: $settings.startsScreenSaver)
                        .resetMenu($settings.startsScreenSaver, to: KeepAwakeSettings.defaultStartsScreenSaver)
                }
                if settings.isEnabled {
                    Section("Status") {
                        LabeledContent("Power source") {
                            Text(status.isOnBattery ? String(localized: "Battery") : String(localized: "Power adapter"))
                        }
                        // Refreshed every second while the pane is open, so the state follows
                        // what the Mac is doing and the countdown ticks.
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            VStack(spacing: 0) {
                                LabeledContent("State") {
                                    Text(stateText)
                                }
                                if let remaining = status.remaining {
                                    Divider().padding(.vertical, 8)
                                    LabeledContent("Sleeps in") {
                                        Text(countdownText(remaining))
                                            .monospacedDigit()
                                    }
                                }
                            }
                        }
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

    private func picker(_ title: LocalizedStringKey, selection: Binding<KeepAwakeDuration>) -> some View {
        Picker(title, selection: selection) {
            ForEach(KeepAwakeDuration.allCases) { duration in
                Text(duration.title).tag(duration)
            }
        }
    }

    /// Active while the Mac is being used (input within the last second, or another app keeping
    /// the display on), Inactive while counting down and once the time is up.
    private var stateText: String {
        switch status.state {
        case .off, .paused: return String(localized: "Not keeping awake")
        case .indefinitely: return String(localized: "Always on")
        case .idle: return String(localized: "Inactive, macOS sleep settings apply")
        case .active:
            if status.otherAppKeepsDisplayOn { return String(localized: "Active, an app keeps the display on") }
            return status.idleTime < Self.activeWindow ? String(localized: "Active") : String(localized: "Inactive")
        }
    }

    /// How recent input must be to count as being used right now.
    private static let activeWindow: TimeInterval = 1

    /// Whole seconds left, so it reads 0:00 during the last second; the full time while the
    /// Mac is being used.
    private func countdownText(_ remaining: TimeInterval) -> String {
        guard let limit = status.limit else { return "" }
        return Self.countdown(status.idleTime < Self.activeWindow ? limit : remaining.rounded(.down))
    }

    /// "4:05" or "1:04:05".
    private static func countdown(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = total / 60 % 60
        let rest = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
    }
}
