import Foundation

enum OverlayStyle: String, CaseIterable, Identifiable {
    case stack
    case ring
    case carousel
    case deck
    case grid

    var id: Self { self }

    var title: String {
        switch self {
        case .stack: "Stack"
        case .ring: "Ring menu"
        case .carousel: "Carousel"
        case .deck: "Deck"
        case .grid: "Grid"
        }
    }
}

/// User preferences, persisted in UserDefaults.
@MainActor
final class AppSettings: ObservableObject {
    static let maxItemsRange = 5...500

    private let defaults = UserDefaults.standard

    @Published var maxItems: Int {
        didSet { defaults.set(maxItems, forKey: Keys.maxItems) }
    }

    @Published var style: OverlayStyle {
        didSet { defaults.set(style.rawValue, forKey: Keys.style) }
    }

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [Keys.maxItems: 50, Keys.style: OverlayStyle.stack.rawValue])
        maxItems = defaults.integer(forKey: Keys.maxItems)
        style = OverlayStyle(rawValue: defaults.string(forKey: Keys.style) ?? "") ?? .stack
    }

    private enum Keys {
        static let maxItems = "maxItems"
        static let style = "overlayStyle"
    }
}
