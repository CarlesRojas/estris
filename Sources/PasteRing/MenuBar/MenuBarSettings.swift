import Foundation

/// Menu bar preferences, persisted in UserDefaults: the icon, and what the menu shows.
@MainActor
final class MenuBarSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    /// One of `MenuBarIcon.all`.
    @Published var icon: String {
        didSet { defaults.set(icon, forKey: Keys.icon) }
    }

    /// The Volume Mixer's System rows (output and microphone).
    @Published var showsSystem: Bool {
        didSet { defaults.set(showsSystem, forKey: Keys.showsSystem) }
    }

    /// The Volume Mixer's Apps rows.
    @Published var showsApps: Bool {
        didSet { defaults.set(showsApps, forKey: Keys.showsApps) }
    }

    /// Each row's device picker.
    @Published var showsDevices: Bool {
        didSet { defaults.set(showsDevices, forKey: Keys.showsDevices) }
    }

    /// Each row's volume percentage.
    @Published var showsPercentages: Bool {
        didSet { defaults.set(showsPercentages, forKey: Keys.showsPercentages) }
    }

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            Keys.showsSystem: true,
            Keys.showsApps: true,
            Keys.showsDevices: true,
            Keys.showsPercentages: true,
        ])
        icon = defaults.string(forKey: Keys.icon).flatMap { MenuBarIcon.all.contains($0) ? $0 : nil } ?? MenuBarIcon.app
        showsSystem = defaults.bool(forKey: Keys.showsSystem)
        showsApps = defaults.bool(forKey: Keys.showsApps)
        showsDevices = defaults.bool(forKey: Keys.showsDevices)
        showsPercentages = defaults.bool(forKey: Keys.showsPercentages)
    }

    /// PasteRing's icon, and the menu showing everything.
    func reset() {
        icon = MenuBarIcon.app
        showsSystem = true
        showsApps = true
        showsDevices = true
        showsPercentages = true
    }

    private enum Keys {
        static let icon = "menuBarIcon"
        static let showsSystem = "menuBarShowsSystem"
        static let showsApps = "menuBarShowsApps"
        static let showsDevices = "menuBarShowsDevices"
        static let showsPercentages = "menuBarShowsPercentages"
    }
}
