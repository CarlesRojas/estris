import Foundation

/// How long an app may sit with no windows before it is quit.
enum QuitDelay: String, CaseIterable, Identifiable {
    case immediately
    case oneSecond
    case fiveSeconds
    case thirtySeconds

    var id: Self { self }

    var title: String {
        switch self {
        case .immediately: String(localized: "Immediately")
        case .oneSecond: String(localized: "After 1 second")
        case .fiveSeconds: String(localized: "After 5 seconds")
        case .thirtySeconds: String(localized: "After 30 seconds")
        }
    }

    var interval: TimeInterval {
        switch self {
        case .immediately: 0
        case .oneSecond: 1
        case .fiveSeconds: 5
        case .thirtySeconds: 30
        }
    }
}

/// Auto Quit preferences, persisted in UserDefaults.
@MainActor
final class AutoQuitSettings: ObservableObject {
    /// Apps that must keep running without windows, with the reason shown in Settings.
    static let alwaysKept: [String: String] = [
        "com.apple.finder": String(localized: "The Finder always keeps running"),
    ]

    private let defaults = UserDefaults.standard

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.isEnabled) }
    }

    @Published var delay: QuitDelay {
        didSet { defaults.set(delay.rawValue, forKey: Keys.delay) }
    }

    /// Bundle identifiers of apps that are never quit.
    @Published var excludedApps: Set<String> {
        didSet { defaults.set(Array(excludedApps), forKey: Keys.excludedApps) }
    }

    init() {
        let defaults = UserDefaults.standard
        // Off until the user turns it on: quitting apps is not something to start doing
        // unasked.
        defaults.register(defaults: [Keys.isEnabled: false, Keys.delay: QuitDelay.oneSecond.rawValue])
        isEnabled = defaults.bool(forKey: Keys.isEnabled)
        delay = QuitDelay(rawValue: defaults.string(forKey: Keys.delay) ?? "") ?? .oneSecond
        excludedApps = Set(defaults.stringArray(forKey: Keys.excludedApps) ?? [])
    }

    /// Back to the default delay; the on/off switch and excluded apps stay as they are.
    func reset() {
        delay = .oneSecond
    }

    func keepsRunning(_ bundleID: String?) -> Bool {
        guard let bundleID else { return true }
        return Self.alwaysKept[bundleID] != nil || excludedApps.contains(bundleID)
    }

    private enum Keys {
        static let isEnabled = "autoQuitEnabled"
        static let delay = "autoQuitDelay"
        static let excludedApps = "autoQuitExcludedApps"
    }
}
