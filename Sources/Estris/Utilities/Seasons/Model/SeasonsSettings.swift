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
    static let defaultAmount: Double = 1
    static let amountRange: ClosedRange<Double> = 0.25...3
    static let defaultWindowLimit: Double = 150
    static let windowLimitRange: ClosedRange<Double> = 0...600
    static let defaultBottomLimit: Double = 800
    static let bottomLimitRange: ClosedRange<Double> = 0...3000
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
    @Published var amount: Double {
        didSet { defaults.set(amount, forKey: Keys.amount) }
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
            Keys.amount: Self.defaultAmount,
            Keys.windowLimit: Self.defaultWindowLimit,
            Keys.bottomLimit: Self.defaultBottomLimit,
            Keys.pausesOnBattery: Self.defaultPausesOnBattery,
            Keys.pausesInFullScreen: Self.defaultPausesInFullScreen,
        ])
        isEnabled = defaults.bool(forKey: Keys.isEnabled)
        season = SeasonChoice(rawValue: defaults.string(forKey: Keys.season) ?? "") ?? Self.defaultSeason
        layer = SeasonsLayer(rawValue: defaults.string(forKey: Keys.layer) ?? "") ?? Self.defaultLayer
        amount = defaults.double(forKey: Keys.amount)
        windowLimit = defaults.double(forKey: Keys.windowLimit)
        bottomLimit = defaults.double(forKey: Keys.bottomLimit)
        pausesOnBattery = defaults.bool(forKey: Keys.pausesOnBattery)
        pausesInFullScreen = defaults.bool(forKey: Keys.pausesInFullScreen)
    }

    /// Back to the defaults; the on/off switch stays.
    func reset() {
        season = Self.defaultSeason
        layer = Self.defaultLayer
        amount = Self.defaultAmount
        windowLimit = Self.defaultWindowLimit
        bottomLimit = Self.defaultBottomLimit
        pausesOnBattery = Self.defaultPausesOnBattery
        pausesInFullScreen = Self.defaultPausesInFullScreen
    }

    private enum Keys {
        static let isEnabled = "seasonsEnabled"
        static let season = "seasonsSeason"
        static let layer = "seasonsLayer"
        static let amount = "seasonsAmount"
        static let windowLimit = "seasonsWindowLimit"
        static let bottomLimit = "seasonsBottomLimit"
        static let pausesOnBattery = "seasonsPausesOnBattery"
        static let pausesInFullScreen = "seasonsPausesInFullScreen"
    }
}
