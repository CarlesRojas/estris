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

    /// Moving faster than this, in points per second, is passing through: windows crossed
    /// aren't focused.
    @Published var passThroughSpeed: Double {
        didSet { defaults.set(passThroughSpeed, forKey: Keys.passThroughSpeed) }
    }

    static let defaultPassThroughSpeed: Double = 800
    static let passThroughSpeeds: ClosedRange<Double> = 200...3000

    /// Bundle identifiers of apps whose windows are never focused by hovering.
    @Published var excludedApps: Set<String> {
        didSet { defaults.set(Array(excludedApps), forKey: Keys.excludedApps) }
    }

    init() {
        let defaults = UserDefaults.standard
        isEnabled = defaults.bool(forKey: Keys.isEnabled)
        delay = defaults.object(forKey: Keys.delay) == nil ? .ms100 : FocusDelay(rawValue: defaults.integer(forKey: Keys.delay)) ?? .ms100
        passThroughSpeed = defaults.object(forKey: Keys.passThroughSpeed) == nil
            ? Self.defaultPassThroughSpeed
            : min(max(defaults.double(forKey: Keys.passThroughSpeed), Self.passThroughSpeeds.lowerBound), Self.passThroughSpeeds.upperBound)
        excludedApps = Set(defaults.stringArray(forKey: Keys.excludedApps) ?? [])
    }

    /// Back to the default delay and speed; the on/off switch and excluded apps stay as they are.
    func reset() {
        delay = .ms100
        passThroughSpeed = Self.defaultPassThroughSpeed
    }

    private enum Keys {
        static let isEnabled = "focusFollowsMouseEnabled"
        static let delay = "focusFollowsMouseDelay"
        static let passThroughSpeed = "focusFollowsMousePassThroughSpeed"
        static let excludedApps = "focusFollowsMouseExcludedApps"
    }
}
