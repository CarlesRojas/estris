import Foundation

/// Menu bar preferences, persisted in UserDefaults: the icon, and what the menu shows.
@MainActor
final class MenuBarSettings: ObservableObject {
    /// What each setting is at first, for Reset to Defaults and each row's Reset to Default.
    enum Default {
        static let icon = MenuBarIcon.app
        static let iconColor: String? = nil
        static let showsSystem = true
        static let showsOutput = true
        static let showsInput = true
        static let showsApps = true
        static let showsDevices = true
        static let showsPercentages = false
        static let showsClipboardHistory = false
        static let showsClearHistory = true
        static let showsColorPicker = true
        static let showsRecentColors = false
        static let showsSeasonsFalling = true
        static let showsSeasonsSeason = true
        static let showsSeasonsIntensity = true
        static let showsSeasonsWind = true
    }

    private let defaults = UserDefaults.standard

    /// One of `MenuBarIcon.all`.
    @Published var icon: String {
        didSet { defaults.set(icon, forKey: Keys.icon) }
    }

    /// The icon's colour as sRGB hex ("FF8000"); nil draws it in the menu bar's own colour.
    @Published var iconColor: String? {
        didSet { defaults.set(iconColor, forKey: Keys.iconColor) }
    }

    /// The Volume Mixer's System rows (output and microphone).
    @Published var showsSystem: Bool {
        didSet { defaults.set(showsSystem, forKey: Keys.showsSystem) }
    }

    /// Within the System rows: the output, and the microphone.
    @Published var showsOutput: Bool {
        didSet { defaults.set(showsOutput, forKey: Keys.showsOutput) }
    }

    @Published var showsInput: Bool {
        didSet { defaults.set(showsInput, forKey: Keys.showsInput) }
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

    /// The most recent clipboard entries, to paste with a click.
    @Published var showsClipboardHistory: Bool {
        didSet { defaults.set(showsClipboardHistory, forKey: Keys.showsClipboardHistory) }
    }

    /// How many of them, 1 to `maxClipboardEntries`.
    @Published var clipboardEntries: Int {
        didSet { defaults.set(clipboardEntries, forKey: Keys.clipboardEntries) }
    }

    /// A button that clears the clipboard history.
    @Published var showsClearHistory: Bool {
        didSet { defaults.set(showsClearHistory, forKey: Keys.showsClearHistory) }
    }

    /// A button that starts picking a color.
    @Published var showsColorPicker: Bool {
        didSet { defaults.set(showsColorPicker, forKey: Keys.showsColorPicker) }
    }

    /// The colors picked lately, to copy with a click.
    @Published var showsRecentColors: Bool {
        didSet { defaults.set(showsRecentColors, forKey: Keys.showsRecentColors) }
    }

    /// Seasons' start/stop button, its season picker, and its intensity and wind sliders.
    @Published var showsSeasonsFalling: Bool {
        didSet { defaults.set(showsSeasonsFalling, forKey: Keys.showsSeasonsFalling) }
    }

    @Published var showsSeasonsSeason: Bool {
        didSet { defaults.set(showsSeasonsSeason, forKey: Keys.showsSeasonsSeason) }
    }

    @Published var showsSeasonsIntensity: Bool {
        didSet { defaults.set(showsSeasonsIntensity, forKey: Keys.showsSeasonsIntensity) }
    }

    @Published var showsSeasonsWind: Bool {
        didSet { defaults.set(showsSeasonsWind, forKey: Keys.showsSeasonsWind) }
    }

    /// Whether the menu has anything of Seasons to show.
    var showsSeasons: Bool {
        showsSeasonsFalling || showsSeasonsSeason || showsSeasonsIntensity || showsSeasonsWind
    }

    static let maxClipboardEntries = 10
    static let defaultClipboardEntries = 5

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            Keys.showsSystem: Default.showsSystem,
            Keys.showsOutput: Default.showsOutput,
            Keys.showsInput: Default.showsInput,
            Keys.showsApps: Default.showsApps,
            Keys.showsDevices: Default.showsDevices,
            Keys.showsPercentages: Default.showsPercentages,
            Keys.showsClipboardHistory: Default.showsClipboardHistory,
            Keys.clipboardEntries: Self.defaultClipboardEntries,
            Keys.showsClearHistory: Default.showsClearHistory,
            Keys.showsColorPicker: Default.showsColorPicker,
            Keys.showsRecentColors: Default.showsRecentColors,
            Keys.showsSeasonsFalling: Default.showsSeasonsFalling,
            Keys.showsSeasonsSeason: Default.showsSeasonsSeason,
            Keys.showsSeasonsIntensity: Default.showsSeasonsIntensity,
            Keys.showsSeasonsWind: Default.showsSeasonsWind,
        ])
        icon = defaults.string(forKey: Keys.icon).flatMap { MenuBarIcon.all.contains($0) ? $0 : nil } ?? Default.icon
        iconColor = defaults.string(forKey: Keys.iconColor)
        showsSystem = defaults.bool(forKey: Keys.showsSystem)
        showsOutput = defaults.bool(forKey: Keys.showsOutput)
        showsInput = defaults.bool(forKey: Keys.showsInput)
        showsApps = defaults.bool(forKey: Keys.showsApps)
        showsDevices = defaults.bool(forKey: Keys.showsDevices)
        showsPercentages = defaults.bool(forKey: Keys.showsPercentages)
        showsClipboardHistory = defaults.bool(forKey: Keys.showsClipboardHistory)
        clipboardEntries = min(max(defaults.integer(forKey: Keys.clipboardEntries), 1), Self.maxClipboardEntries)
        showsClearHistory = defaults.bool(forKey: Keys.showsClearHistory)
        showsColorPicker = defaults.bool(forKey: Keys.showsColorPicker)
        showsRecentColors = defaults.bool(forKey: Keys.showsRecentColors)
        showsSeasonsFalling = defaults.bool(forKey: Keys.showsSeasonsFalling)
        showsSeasonsSeason = defaults.bool(forKey: Keys.showsSeasonsSeason)
        showsSeasonsIntensity = defaults.bool(forKey: Keys.showsSeasonsIntensity)
        showsSeasonsWind = defaults.bool(forKey: Keys.showsSeasonsWind)
    }

    /// Estris's icon, and the menu as it starts out.
    func reset() {
        icon = Default.icon
        iconColor = Default.iconColor
        showsSystem = Default.showsSystem
        showsOutput = Default.showsOutput
        showsInput = Default.showsInput
        showsApps = Default.showsApps
        showsDevices = Default.showsDevices
        showsPercentages = Default.showsPercentages
        showsClipboardHistory = Default.showsClipboardHistory
        clipboardEntries = Self.defaultClipboardEntries
        showsClearHistory = Default.showsClearHistory
        showsColorPicker = Default.showsColorPicker
        showsRecentColors = Default.showsRecentColors
        showsSeasonsFalling = Default.showsSeasonsFalling
        showsSeasonsSeason = Default.showsSeasonsSeason
        showsSeasonsIntensity = Default.showsSeasonsIntensity
        showsSeasonsWind = Default.showsSeasonsWind
    }

    private enum Keys {
        static let icon = "menuBarIcon"
        static let iconColor = "menuBarIconColor"
        static let showsSystem = "menuBarShowsSystem"
        static let showsOutput = "menuBarShowsOutput"
        static let showsInput = "menuBarShowsInput"
        static let showsApps = "menuBarShowsApps"
        static let showsDevices = "menuBarShowsDevices"
        static let showsPercentages = "menuBarShowsPercentages"
        static let showsClipboardHistory = "menuBarShowsClipboardHistory"
        static let clipboardEntries = "menuBarClipboardEntries"
        static let showsClearHistory = "menuBarShowsClearHistory"
        static let showsColorPicker = "menuBarShowsColorPicker"
        static let showsRecentColors = "menuBarShowsRecentColors"
        static let showsSeasonsFalling = "menuBarShowsSeasonsFalling"
        static let showsSeasonsSeason = "menuBarShowsSeasonsSeason"
        static let showsSeasonsIntensity = "menuBarShowsSeasonsIntensity"
        static let showsSeasonsWind = "menuBarShowsSeasonsWind"
    }
}
