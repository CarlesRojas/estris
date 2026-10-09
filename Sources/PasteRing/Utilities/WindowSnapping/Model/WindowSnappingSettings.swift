import Foundation

/// A drag-to-snap area, switched on or off on its own.
enum SnapGesture: String, CaseIterable, Codable, Identifiable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case maximize
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case thirds
    case twoThirds

    var id: Self { self }

    var title: String {
        switch self {
        case .topLeft: String(localized: "Top left corner")
        case .topRight: String(localized: "Top right corner")
        case .bottomLeft: String(localized: "Bottom left corner")
        case .bottomRight: String(localized: "Bottom right corner")
        case .maximize: String(localized: "Top edge: maximize")
        case .leftHalf: String(localized: "Left edge: left half")
        case .rightHalf: String(localized: "Right edge: right half")
        case .topHalf: String(localized: "Side edges near the top: top half")
        case .bottomHalf: String(localized: "Side edges near the bottom: bottom half")
        case .thirds: String(localized: "Bottom edge: thirds")
        case .twoThirds: String(localized: "Bottom edge: two thirds when sliding to the middle")
        }
    }

    /// On unless it splits the screen into top and bottom.
    static let defaults: Set<SnapGesture> = Set(allCases).subtracting([.topHalf, .bottomHalf])
}

/// Window Snapping preferences, persisted in UserDefaults.
@MainActor
final class WindowSnappingSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.isEnabled) }
    }

    /// Snap a window by dragging it to a screen edge or corner.
    @Published var snapsByDragging: Bool {
        didSet { defaults.set(snapsByDragging, forKey: Keys.snapsByDragging) }
    }

    /// Resizing a window also resizes the windows sharing the edge being dragged.
    @Published var resizesTogether: Bool {
        didSet { defaults.set(resizesTogether, forKey: Keys.resizesTogether) }
    }

    /// How far into the screen, in points, the edges reach for dragging.
    @Published var edgeArea: Double {
        didSet { defaults.set(edgeArea, forKey: Keys.edgeArea) }
    }

    static let edgeAreaRange: ClosedRange<Double> = 8...150

    /// The drag areas that snap.
    @Published var gestures: Set<SnapGesture> {
        didSet { defaults.set(gestures.map(\.rawValue), forKey: Keys.gestures) }
    }

    /// Shortcut per action; actions left out use their default.
    @Published var shortcuts: [SnapAction: Shortcut] {
        didSet { defaults.set(try? JSONEncoder().encode(shortcuts), forKey: Keys.shortcuts) }
    }

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            Keys.isEnabled: false,
            Keys.snapsByDragging: true,
            Keys.resizesTogether: true,
            Keys.edgeArea: 32.0,
            Keys.gestures: SnapGesture.defaults.map(\.rawValue),
        ])
        isEnabled = defaults.bool(forKey: Keys.isEnabled)
        snapsByDragging = defaults.bool(forKey: Keys.snapsByDragging)
        resizesTogether = defaults.bool(forKey: Keys.resizesTogether)
        edgeArea = defaults.double(forKey: Keys.edgeArea)
        gestures = Set((defaults.stringArray(forKey: Keys.gestures) ?? []).compactMap(SnapGesture.init(rawValue:)))
        shortcuts = defaults.data(forKey: Keys.shortcuts).flatMap { try? JSONDecoder().decode([SnapAction: Shortcut].self, from: $0) } ?? [:]
    }

    func shortcut(for action: SnapAction) -> Shortcut {
        shortcuts[action] ?? action.defaultShortcut
    }

    func resetShortcuts() {
        shortcuts = [:]
    }

    private enum Keys {
        static let isEnabled = "windowSnappingEnabled"
        static let snapsByDragging = "windowSnappingByDragging"
        static let resizesTogether = "windowSnappingResizesTogether"
        static let shortcuts = "windowSnappingShortcuts"
        static let edgeArea = "windowSnappingEdgeArea"
        static let gestures = "windowSnappingGestures"
    }
}
