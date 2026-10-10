import Foundation

/// How long the pointer rests on a window before it is focused.
enum FocusDelay: Int, CaseIterable, Identifiable {
    case immediately = 0
    case ms100 = 100
    case ms250 = 250
    case ms500 = 500
    case ms1000 = 1000

    var id: Self { self }

    var seconds: TimeInterval { TimeInterval(rawValue) / 1000 }

    /// "Immediately", or "250 ms" in the app's language.
    var title: String {
        if self == .immediately { return String(localized: "Immediately") }
        return Measurement(value: Double(rawValue), unit: UnitDuration.milliseconds)
            .formatted(.measurement(width: .abbreviated))
    }
}

/// Focus Follows Mouse preferences, persisted in UserDefaults.
@MainActor
final class FocusFollowsMouseSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.isEnabled) }
    }

    @Published var delay: FocusDelay {
        didSet { defaults.set(delay.rawValue, forKey: Keys.delay) }
    }

    /// Bundle identifiers of apps whose windows are never focused by hovering.
    @Published var excludedApps: Set<String> {
        didSet { defaults.set(Array(excludedApps), forKey: Keys.excludedApps) }
    }

    init() {
        let defaults = UserDefaults.standard
        isEnabled = defaults.bool(forKey: Keys.isEnabled)
        delay = defaults.object(forKey: Keys.delay) == nil ? .immediately : FocusDelay(rawValue: defaults.integer(forKey: Keys.delay)) ?? .immediately
        excludedApps = Set(defaults.stringArray(forKey: Keys.excludedApps) ?? [])
    }

    /// Back to the default delay; the on/off switch and excluded apps stay as they are.
    func reset() {
        delay = .immediately
    }

    private enum Keys {
        static let isEnabled = "focusFollowsMouseEnabled"
        static let delay = "focusFollowsMouseDelay"
        static let excludedApps = "focusFollowsMouseExcludedApps"
    }
}
