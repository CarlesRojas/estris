import Foundation

/// Where the weather widget sits.
enum WidgetPlacement: String, CaseIterable, Identifiable {
    /// On the desktop, behind every window, as a widget.
    case desktop
    /// Above other windows, always in view.
    case aboveWindows

    var id: Self { self }

    var title: String {
        switch self {
        case .desktop: String(localized: "On the desktop")
        case .aboveWindows: String(localized: "Above windows")
        }
    }
}

/// Weather widget preferences, persisted in UserDefaults. What the widget changes (falling,
/// wind, intensity, season) lives in `SeasonsSettings`, so it is kept too.
@MainActor
final class WeatherWidgetSettings: ObservableObject {
    enum Default {
        static let showsSeason = true
        static let showsIntensity = true
        static let showsWind = true
        static let placement = WidgetPlacement.desktop
        static let collectsWeather = true
    }

    private let defaults = UserDefaults.standard

    /// Off by default: the widget is optional.
    @Published var isShown: Bool {
        didSet { defaults.set(isShown, forKey: Keys.isShown) }
    }

    @Published var showsSeason: Bool {
        didSet { defaults.set(showsSeason, forKey: Keys.showsSeason) }
    }

    @Published var showsIntensity: Bool {
        didSet { defaults.set(showsIntensity, forKey: Keys.showsIntensity) }
    }

    @Published var showsWind: Bool {
        didSet { defaults.set(showsWind, forKey: Keys.showsWind) }
    }

    @Published var placement: WidgetPlacement {
        didSet { defaults.set(placement.rawValue, forKey: Keys.placement) }
    }

    /// Snow, sand, petals and leaves pile up on the widget too.
    @Published var collectsWeather: Bool {
        didSet { defaults.set(collectsWeather, forKey: Keys.collectsWeather) }
    }

    /// Where its top left corner was left, in screen coordinates; nil until it is moved.
    var topLeft: CGPoint? {
        get {
            guard defaults.object(forKey: Keys.x) != nil else { return nil }
            return CGPoint(x: defaults.double(forKey: Keys.x), y: defaults.double(forKey: Keys.top))
        }
        set {
            if let newValue {
                defaults.set(Double(newValue.x), forKey: Keys.x)
                defaults.set(Double(newValue.y), forKey: Keys.top)
            } else {
                defaults.removeObject(forKey: Keys.x)
                defaults.removeObject(forKey: Keys.top)
            }
        }
    }

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            Keys.showsSeason: Default.showsSeason,
            Keys.showsIntensity: Default.showsIntensity,
            Keys.showsWind: Default.showsWind,
            Keys.collectsWeather: Default.collectsWeather,
        ])
        isShown = defaults.bool(forKey: Keys.isShown)
        showsSeason = defaults.bool(forKey: Keys.showsSeason)
        showsIntensity = defaults.bool(forKey: Keys.showsIntensity)
        showsWind = defaults.bool(forKey: Keys.showsWind)
        placement = WidgetPlacement(rawValue: defaults.string(forKey: Keys.placement) ?? "") ?? Default.placement
        collectsWeather = defaults.bool(forKey: Keys.collectsWeather)
    }

    /// Back to the default controls and placement; whether it shows, and where it was left,
    /// stay.
    func reset() {
        showsSeason = Default.showsSeason
        showsIntensity = Default.showsIntensity
        showsWind = Default.showsWind
        placement = Default.placement
        collectsWeather = Default.collectsWeather
    }

    private enum Keys {
        static let isShown = "seasonsWidgetShown"
        static let showsSeason = "seasonsWidgetShowsSeason"
        static let showsIntensity = "seasonsWidgetShowsIntensity"
        static let showsWind = "seasonsWidgetShowsWind"
        static let placement = "seasonsWidgetPlacement"
        static let collectsWeather = "seasonsWidgetCollectsWeather"
        static let x = "seasonsWidgetX"
        static let top = "seasonsWidgetTop"
    }
}
