import Foundation

/// How long the Mac may be idle before Keep Awake lets it sleep.
enum KeepAwakeDuration: String, CaseIterable, Identifiable {
    case off
    /// For trying it out.
    case tenSeconds
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
        case .tenSeconds: String(localized: "10 seconds")
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
        case .tenSeconds: 10
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
    private let defaults = UserDefaults.standard

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.isEnabled) }
    }

    /// How long while on the power adapter.
    @Published var onPower: KeepAwakeDuration {
        didSet { defaults.set(onPower.rawValue, forKey: Keys.onPower) }
    }

    /// How long while on battery.
    @Published var onBattery: KeepAwakeDuration {
        didSet { defaults.set(onBattery.rawValue, forKey: Keys.onBattery) }
    }

    init() {
        let defaults = UserDefaults.standard
        isEnabled = defaults.bool(forKey: Keys.isEnabled)
        onPower = KeepAwakeDuration(rawValue: defaults.string(forKey: Keys.onPower) ?? "") ?? .indefinitely
        onBattery = KeepAwakeDuration(rawValue: defaults.string(forKey: Keys.onBattery) ?? "") ?? .oneHour
    }

    private enum Keys {
        static let isEnabled = "keepAwakeEnabled"
        static let onPower = "keepAwakeOnPower"
        static let onBattery = "keepAwakeOnBattery"
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
        /// Idle for the chosen time: macOS's own sleep settings apply until it is used again.
        case idle
    }

    @Published var state = State.off
    @Published var isOnBattery = false
}
