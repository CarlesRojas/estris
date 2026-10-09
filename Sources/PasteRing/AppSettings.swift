import Foundation
import SwiftUI

/// Order here is the order shown in Settings.
enum OverlayStyle: String, CaseIterable, Identifiable {
    case simple
    case grid
    case carousel
    case stack
    case ring

    var id: Self { self }

    var title: String {
        switch self {
        case .simple: "Default"
        case .stack: "Stack"
        case .carousel: "Carousel"
        case .grid: "Grid"
        case .ring: "Ring menu"
        }
    }
}

/// User preferences, persisted in UserDefaults.
@MainActor
final class AppSettings: ObservableObject {
    static let maxItemsRange = 5...500
    static let ringSizeRange = 3...12
    static let gridColumns = 4
    static let gridSizeRange = 8...24
    static let simpleWidthRange: ClosedRange<Double> = 360...900
    static let simpleHeightRange: ClosedRange<Double> = 120...420
    static let gridCardWidthRange: ClosedRange<Double> = 160...420
    static let carouselSizeRange: ClosedRange<Double> = 180...420
    static let stackWidthRange: ClosedRange<Double> = 360...800
    static let stackHeightRange: ClosedRange<Double> = 120...360

    private let defaults = UserDefaults.standard

    @Published var maxItems: Int {
        didSet { defaults.set(maxItems, forKey: Keys.maxItems) }
    }

    /// How many of the most recent entries the ring menu shows. All of them fit on the circle.
    @Published var ringSize: Int {
        didSet { defaults.set(ringSize, forKey: Keys.ringSize) }
    }

    /// How many of the most recent entries the grid shows, all at once. A multiple of the columns.
    @Published var gridSize: Int {
        didSet { defaults.set(gridSize, forKey: Keys.gridSize) }
    }

    @Published var gridCardWidth: Double {
        didSet { defaults.set(gridCardWidth, forKey: Keys.gridCardWidth) }
    }

    @Published var carouselWidth: Double {
        didSet { defaults.set(carouselWidth, forKey: Keys.carouselWidth) }
    }

    @Published var carouselHeight: Double {
        didSet { defaults.set(carouselHeight, forKey: Keys.carouselHeight) }
    }

    @Published var stackWidth: Double {
        didSet { defaults.set(stackWidth, forKey: Keys.stackWidth) }
    }

    @Published var stackHeight: Double {
        didSet { defaults.set(stackHeight, forKey: Keys.stackHeight) }
    }

    @Published var simpleWidth: Double {
        didSet { defaults.set(simpleWidth, forKey: Keys.simpleWidth) }
    }

    @Published var simpleHeight: Double {
        didSet { defaults.set(simpleHeight, forKey: Keys.simpleHeight) }
    }

    @Published var style: OverlayStyle {
        didSet { defaults.set(style.rawValue, forKey: Keys.style) }
    }

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [Keys.maxItems: 50])
        defaults.register(defaults: Self.appearanceDefaults)
        maxItems = defaults.integer(forKey: Keys.maxItems)
        ringSize = defaults.integer(forKey: Keys.ringSize)
        gridSize = defaults.integer(forKey: Keys.gridSize)
        gridCardWidth = defaults.double(forKey: Keys.gridCardWidth)
        simpleWidth = defaults.double(forKey: Keys.simpleWidth)
        simpleHeight = defaults.double(forKey: Keys.simpleHeight)
        carouselWidth = defaults.double(forKey: Keys.carouselWidth)
        carouselHeight = defaults.double(forKey: Keys.carouselHeight)
        stackWidth = defaults.double(forKey: Keys.stackWidth)
        stackHeight = defaults.double(forKey: Keys.stackHeight)
        style = OverlayStyle(rawValue: defaults.string(forKey: Keys.style) ?? "") ?? .simple
    }

    /// How many entries the overlay shows for the current style.
    var visibleLimit: Int? {
        switch style {
        case .ring: ringSize
        case .grid: gridSize
        case .simple, .stack, .carousel: nil
        }
    }

    /// Defaults for the settings shown in the Appearance tab. Add new ones here so
    /// Reset to Defaults covers them.
    private static let appearanceDefaults: [String: Any] = [
        Keys.style: OverlayStyle.simple.rawValue,
        Keys.ringSize: 8,
        Keys.gridSize: 12,
        Keys.gridCardWidth: 256.0,
        Keys.simpleWidth: 560.0,
        Keys.simpleHeight: 256.0,
        Keys.carouselWidth: 260.0,
        Keys.carouselHeight: 260.0,
        Keys.stackWidth: 520.0,
        Keys.stackHeight: 170.0,
    ]

    func resetAppearance() {
        for key in Self.appearanceDefaults.keys {
            defaults.removeObject(forKey: key)
        }
        style = OverlayStyle(rawValue: defaults.string(forKey: Keys.style) ?? "") ?? .simple
        ringSize = defaults.integer(forKey: Keys.ringSize)
        gridSize = defaults.integer(forKey: Keys.gridSize)
        gridCardWidth = defaults.double(forKey: Keys.gridCardWidth)
        simpleWidth = defaults.double(forKey: Keys.simpleWidth)
        simpleHeight = defaults.double(forKey: Keys.simpleHeight)
        carouselWidth = defaults.double(forKey: Keys.carouselWidth)
        carouselHeight = defaults.double(forKey: Keys.carouselHeight)
        stackWidth = defaults.double(forKey: Keys.stackWidth)
        stackHeight = defaults.double(forKey: Keys.stackHeight)
    }

    /// Binding that keeps typed or stepped values inside `range`.
    func clamped(_ keyPath: ReferenceWritableKeyPath<AppSettings, Int>, to range: ClosedRange<Int>) -> Binding<Int> {
        Binding(
            get: { self[keyPath: keyPath] },
            set: { self[keyPath: keyPath] = min(max($0, range.lowerBound), range.upperBound) }
        )
    }

    private enum Keys {
        static let maxItems = "maxItems"
        static let ringSize = "ringSize"
        static let gridSize = "gridSize"
        static let gridCardWidth = "gridCardWidth"
        static let simpleWidth = "simpleWidth"
        static let simpleHeight = "simpleHeight"
        static let carouselWidth = "carouselWidth"
        static let carouselHeight = "carouselHeight"
        static let stackWidth = "stackWidth"
        static let stackHeight = "stackHeight"
        static let style = "overlayStyle"
    }
}
