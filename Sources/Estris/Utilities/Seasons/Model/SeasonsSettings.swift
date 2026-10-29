import Foundation

/// Which season's effect plays: the one of today's date, or one chosen.
enum SeasonChoice: String, CaseIterable, Identifiable {
    case automatic
    case winter
    case spring
    case summer
    case autumn

    var id: Self { self }

    var title: String {
        switch self {
        case .automatic: String(localized: "Automatic")
        case .winter: String(localized: "Winter: snow")
        case .spring: String(localized: "Spring: petals")
        case .summer: String(localized: "Summer: sand")
        case .autumn: String(localized: "Autumn: leaves")
        }
    }

    /// The season that plays: a chosen one, or today's.
    var season: Season {
        switch self {
        case .automatic: Season.current()
        case .winter: .winter
        case .spring: .spring
        case .summer: .summer
        case .autumn: .autumn
        }
    }
}

enum Season {
    case winter
    case spring
    case summer
    case autumn

    var title: String {
        switch self {
        case .winter: String(localized: "Winter")
        case .spring: String(localized: "Spring")
        case .summer: String(localized: "Summer")
        case .autumn: String(localized: "Autumn")
        }
    }

    var symbol: String {
        switch self {
        case .winter: "snowflake"
        case .spring: "camera.macro"
        case .summer: "sun.max"
        case .autumn: "leaf"
        }
    }

    /// The meteorological season of a date (whole months: winter is December to February in
    /// the north), flipped south of the equator, told by the Mac's region.
    static func current(_ date: Date = Date()) -> Season {
        let month = Calendar(identifier: .gregorian).component(.month, from: date)
        let north: [Season] = [.winter, .spring, .summer, .autumn]
        let index = (month % 12) / 3
        let south = southernRegions.contains(Locale.current.region?.identifier ?? "")
        return north[south ? (index + 2) % 4 : index]
    }

    /// Countries wholly or mostly south of the equator.
    private static let southernRegions: Set<String> = [
        "AR", "AU", "BO", "BR", "BW", "CL", "FJ", "LS", "MG", "MU", "MW", "MZ", "NA", "NZ", "PE",
        "PY", "SZ", "UY", "ZA", "ZM", "ZW", "AO", "TZ", "PG", "NC", "PF", "WS", "TO", "RE",
    ]
}

/// Where the particles fall.
enum SeasonsLayer: String, CaseIterable, Identifiable {
    case inFront
    case behind

    var id: Self { self }

    var title: String {
        switch self {
        case .inFront: String(localized: "In front of windows")
        case .behind: String(localized: "Behind windows")
        }
    }
}

/// Seasons preferences, persisted in UserDefaults.
@MainActor
final class SeasonsSettings: ObservableObject {
    static let defaultSeason = SeasonChoice.automatic
    static let defaultLayer = SeasonsLayer.inFront
    static let defaultDensity: Double = 1
    static let densityRange: ClosedRange<Double> = 0.1...4
    static let defaultWindowLimit: Double = 500
    static let windowLimitRange: ClosedRange<Double> = 0...2000
    static let defaultBottomLimit: Double = 3000
    static let bottomLimitRange: ClosedRange<Double> = 0...10000
    static let defaultWind: Double = 0
    /// Wind as a share of the strongest: negative blows to the left.
    static let windRange: ClosedRange<Double> = -1...1
    /// The strongest wind, in points per second.
    static let strongestWind: Double = 140
    static let defaultPausesOnBattery = true
    static let defaultPausesInFullScreen = true

    private let defaults = UserDefaults.standard

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.isEnabled) }
    }

    @Published var season: SeasonChoice {
        didSet { defaults.set(season.rawValue, forKey: Keys.season) }
    }

    @Published var layer: SeasonsLayer {
        didSet { defaults.set(layer.rawValue, forKey: Keys.layer) }
    }

    /// How much falls, as a multiple of the season's own rate.
    @Published var density: Double {
        didSet { defaults.set(density, forKey: Keys.density) }
    }

    /// Whether anything falls; what is already there stays. Started and stopped from the
    /// menu bar or the pane.
    @Published var isFalling: Bool {
        didSet { defaults.set(isFalling, forKey: Keys.isFalling) }
    }

    /// The wind, from strongest to the left (-1) to strongest to the right (1).
    @Published var wind: Double {
        didSet { defaults.set(wind, forKey: Keys.wind) }
    }

    /// How many particles a window's top edge holds; more melt away the oldest.
    @Published var windowLimit: Double {
        didSet { defaults.set(windowLimit, forKey: Keys.windowLimit) }
    }

    /// How many particles the bottom of each screen holds.
    @Published var bottomLimit: Double {
        didSet { defaults.set(bottomLimit, forKey: Keys.bottomLimit) }
    }

    /// Stops while on battery or in Low Power Mode.
    @Published var pausesOnBattery: Bool {
        didSet { defaults.set(pausesOnBattery, forKey: Keys.pausesOnBattery) }
    }

    /// Hides on a screen showing a full screen app.
    @Published var pausesInFullScreen: Bool {
        didSet { defaults.set(pausesInFullScreen, forKey: Keys.pausesInFullScreen) }
    }

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            Keys.density: Self.defaultDensity,
            Keys.windowLimit: Self.defaultWindowLimit,
            Keys.bottomLimit: Self.defaultBottomLimit,
            Keys.pausesOnBattery: Self.defaultPausesOnBattery,
            Keys.pausesInFullScreen: Self.defaultPausesInFullScreen,
            Keys.isFalling: true,
        ])
        isEnabled = defaults.bool(forKey: Keys.isEnabled)
        season = SeasonChoice(rawValue: defaults.string(forKey: Keys.season) ?? "") ?? Self.defaultSeason
        layer = SeasonsLayer(rawValue: defaults.string(forKey: Keys.layer) ?? "") ?? Self.defaultLayer
        density = defaults.double(forKey: Keys.density)
        windowLimit = defaults.double(forKey: Keys.windowLimit)
        bottomLimit = defaults.double(forKey: Keys.bottomLimit)
        pausesOnBattery = defaults.bool(forKey: Keys.pausesOnBattery)
        pausesInFullScreen = defaults.bool(forKey: Keys.pausesInFullScreen)
        isFalling = defaults.bool(forKey: Keys.isFalling)
        wind = defaults.double(forKey: Keys.wind)
    }

    /// Back to the defaults; the on/off switch and whether it is falling stay.
    func reset() {
        season = Self.defaultSeason
        wind = Self.defaultWind
        layer = Self.defaultLayer
        density = Self.defaultDensity
        windowLimit = Self.defaultWindowLimit
        bottomLimit = Self.defaultBottomLimit
        pausesOnBattery = Self.defaultPausesOnBattery
        pausesInFullScreen = Self.defaultPausesInFullScreen
    }

    private enum Keys {
        static let isEnabled = "seasonsEnabled"
        static let season = "seasonsSeason"
        static let layer = "seasonsLayer"
        static let density = "seasonsDensity"
        static let windowLimit = "seasonsWindowLimit"
        static let bottomLimit = "seasonsBottomLimit"
        static let pausesOnBattery = "seasonsPausesOnBattery"
        static let pausesInFullScreen = "seasonsPausesInFullScreen"
        static let isFalling = "seasonsFalling"
        static let wind = "seasonsWind"
    }
}
