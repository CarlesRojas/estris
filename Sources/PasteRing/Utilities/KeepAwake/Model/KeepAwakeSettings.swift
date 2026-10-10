import Foundation
import IOKit

/// How long the Mac may be idle before Keep Awake lets it sleep.
enum KeepAwakeDuration: String, CaseIterable, Identifiable {
    case off
    case fifteenMinutes
    case thirtyMinutes
    case oneHour
    case twoHours
    case fourHours
    case eightHours
    case indefinitely

    var id: Self { self }

    var title: String {
        switch self {
        case .off: String(localized: "Don't keep awake")
        case .fifteenMinutes: String(localized: "15 minutes")
        case .thirtyMinutes: String(localized: "30 minutes")
        case .oneHour: String(localized: "1 hour")
        case .twoHours: String(localized: "2 hours")
        case .fourHours: String(localized: "4 hours")
        case .eightHours: String(localized: "8 hours")
        case .indefinitely: String(localized: "Indefinitely")
        }
    }

    /// Nil for no limit; zero for not at all.
    var seconds: TimeInterval? {
        switch self {
        case .off: 0
        case .fifteenMinutes: 15 * 60
        case .thirtyMinutes: 30 * 60
        case .oneHour: 60 * 60
        case .twoHours: 2 * 60 * 60
        case .fourHours: 4 * 60 * 60
        case .eightHours: 8 * 60 * 60
        case .indefinitely: nil
        }
    }
}

/// Keep Awake preferences, persisted in UserDefaults.
@MainActor
final class KeepAwakeSettings: ObservableObject {
    static let defaultOnPower = KeepAwakeDuration.indefinitely
    static let defaultOnBattery = KeepAwakeDuration.oneHour
    static let defaultStartsScreenSaver = true

    private let defaults = UserDefaults.standard

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.isEnabled) }
    }

    /// How long while on the power adapter.
    @Published var onPower: KeepAwakeDuration {
        didSet { defaults.set(onPower.rawValue, forKey: Keys.onPower) }
    }

    /// When the idle time runs out, start the screen saver instead of sleeping.
    @Published var startsScreenSaver: Bool {
        didSet { defaults.set(startsScreenSaver, forKey: Keys.startsScreenSaver) }
    }

    /// How long while on battery.
    @Published var onBattery: KeepAwakeDuration {
        didSet { defaults.set(onBattery.rawValue, forKey: Keys.onBattery) }
    }

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [Keys.startsScreenSaver: Self.defaultStartsScreenSaver])
        isEnabled = defaults.bool(forKey: Keys.isEnabled)
        startsScreenSaver = defaults.bool(forKey: Keys.startsScreenSaver)
        onPower = KeepAwakeDuration(rawValue: defaults.string(forKey: Keys.onPower) ?? "") ?? Self.defaultOnPower
        onBattery = KeepAwakeDuration(rawValue: defaults.string(forKey: Keys.onBattery) ?? "") ?? Self.defaultOnBattery
    }

    /// Back to the default durations and the screen saver; the on/off switch stays.
    func reset() {
        onPower = Self.defaultOnPower
        onBattery = Self.defaultOnBattery
        startsScreenSaver = Self.defaultStartsScreenSaver
    }

    private enum Keys {
        static let isEnabled = "keepAwakeEnabled"
        static let onPower = "keepAwakeOnPower"
        static let onBattery = "keepAwakeOnBattery"
        static let startsScreenSaver = "keepAwakeStartsScreenSaver"
    }
}

/// What Keep Awake is doing right now, for the Settings pane.
@MainActor
final class KeepAwakeStatus: ObservableObject {
    enum State: Equatable {
        case off
        /// On, but the current power source is set to not keep awake.
        case paused
        case indefinitely
        /// Keeping awake, as the Mac was used within the chosen time.
        case active
        /// Idle for the chosen time: the Mac was put to sleep, or macOS's own sleep settings
        /// apply until it is used again.
        case idle
    }

    @Published var state = State.off
    @Published var isOnBattery = false
    /// How long the Mac may be idle on the current power source, for the countdown.
    @Published var limit: TimeInterval?
    /// Whether another app keeps the display on, such as a playing video.
    @Published var otherAppKeepsDisplayOn = false
    /// When another app last stopped keeping the display on, which counts as activity.
    var otherHolderEndedAt = Date.distantPast
    /// When the Mac or its screen last woke, which counts as activity.
    var lastWake = Date.distantPast

    /// Seconds the Mac has been idle: since the last input or another app keeping the
    /// display on.
    var idleTime: TimeInterval {
        min(Self.inputIdleTime, Date().timeIntervalSince(otherHolderEndedAt), Date().timeIntervalSince(lastWake))
    }

    /// Seconds left until the Mac may sleep, while counting down.
    var remaining: TimeInterval? {
        guard state == .active, !otherAppKeepsDisplayOn, let limit else { return nil }
        return max(0, limit - idleTime)
    }

    /// Seconds since the last mouse, keyboard or trackpad input.
    static var inputIdleTime: TimeInterval {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        guard service != 0 else { return 0 }
        defer { IOObjectRelease(service) }
        let value = IORegistryEntryCreateCFProperty(service, "HIDIdleTime" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        guard let nanoseconds = (value as? NSNumber)?.uint64Value else { return 0 }
        return TimeInterval(nanoseconds) / 1_000_000_000
    }
}
