import Foundation

/// Focus Follows Mouse preferences, persisted in UserDefaults.
@MainActor
final class FocusFollowsMouseSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.isEnabled) }
    }

    @Published var delay: HoverDelay {
        didSet { defaults.set(delay.rawValue, forKey: Keys.delay) }
    }

    /// Moving faster than this, in points per second, is passing through: windows crossed
    /// aren't focused.
    @Published var passThroughSpeed: Double {
        didSet { defaults.set(passThroughSpeed, forKey: Keys.passThroughSpeed) }
    }

    static let defaultPassThroughSpeed: Double = 800
    static let defaultDelay = HoverDelay.ms100
    static let passThroughSpeeds: ClosedRange<Double> = 200...3000

    /// Bundle identifiers of apps whose windows are never focused by hovering.
    @Published var excludedApps: Set<String> {
        didSet { defaults.set(Array(excludedApps), forKey: Keys.excludedApps) }
    }

    init() {
        let defaults = UserDefaults.standard
        isEnabled = defaults.bool(forKey: Keys.isEnabled)
        delay = defaults.object(forKey: Keys.delay) == nil ? Self.defaultDelay : HoverDelay(rawValue: defaults.integer(forKey: Keys.delay)) ?? Self.defaultDelay
        passThroughSpeed = defaults.object(forKey: Keys.passThroughSpeed) == nil
            ? Self.defaultPassThroughSpeed
            : min(max(defaults.double(forKey: Keys.passThroughSpeed), Self.passThroughSpeeds.lowerBound), Self.passThroughSpeeds.upperBound)
        excludedApps = Set(defaults.stringArray(forKey: Keys.excludedApps) ?? [])
    }

    /// Back to the default delay and speed; the on/off switch and excluded apps stay as they are.
    func reset() {
        delay = Self.defaultDelay
        passThroughSpeed = Self.defaultPassThroughSpeed
    }

    private enum Keys {
        static let isEnabled = "focusFollowsMouseEnabled"
        static let delay = "focusFollowsMouseDelay"
        static let passThroughSpeed = "focusFollowsMousePassThroughSpeed"
        static let excludedApps = "focusFollowsMouseExcludedApps"
    }
}
