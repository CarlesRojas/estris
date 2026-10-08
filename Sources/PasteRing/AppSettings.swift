import Foundation

enum OverlayStyle: String, CaseIterable, Identifiable {
    case stack
    case ring
    case carousel
    case simple
    case grid

    var id: Self { self }

    var title: String {
        switch self {
        case .stack: "Stack"
        case .ring: "Ring menu"
        case .carousel: "Carousel"
        case .simple: "Simple"
        case .grid: "Grid"
        }
    }
}

/// User preferences, persisted in UserDefaults.
@MainActor
final class AppSettings: ObservableObject {
    static let maxItemsRange = 5...500
    static let ringSizeRange = 3...12

    private let defaults = UserDefaults.standard

    @Published var maxItems: Int {
        didSet { defaults.set(maxItems, forKey: Keys.maxItems) }
    }

    /// How many of the most recent entries the ring menu shows. All of them fit on the circle.
    @Published var ringSize: Int {
        didSet { defaults.set(ringSize, forKey: Keys.ringSize) }
    }

    @Published var glass: GlassStyle {
        didSet { defaults.set(glass.rawValue, forKey: Keys.glass) }
    }

    @Published var style: OverlayStyle {
        didSet { defaults.set(style.rawValue, forKey: Keys.style) }
    }

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [Keys.maxItems: 50, Keys.ringSize: 8, Keys.style: OverlayStyle.stack.rawValue, Keys.glass: GlassStyle.frosted.rawValue])
        maxItems = defaults.integer(forKey: Keys.maxItems)
        ringSize = defaults.integer(forKey: Keys.ringSize)
        glass = GlassStyle(rawValue: defaults.string(forKey: Keys.glass) ?? "") ?? .frosted
        style = OverlayStyle(rawValue: defaults.string(forKey: Keys.style) ?? "") ?? .stack
    }

    private enum Keys {
        static let maxItems = "maxItems"
        static let ringSize = "ringSize"
        static let glass = "glassStyle"
        static let style = "overlayStyle"
    }
}
