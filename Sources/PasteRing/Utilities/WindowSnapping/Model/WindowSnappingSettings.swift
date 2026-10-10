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

    /// Fit snaps to the space left by windows already tiled on the screen.
    @Published var fillsSpace: Bool {
        didSet { defaults.set(fillsSpace, forKey: Keys.fillsSpace) }
    }

    /// How far into the screen, in points, the edges reach for dragging.
    @Published var edgeArea: Double {
        didSet { defaults.set(edgeArea, forKey: Keys.edgeArea) }
    }

    static let edgeAreaRange: ClosedRange<Double> = 8...150
    static let defaultEdgeArea = 64.0

    /// A shortcut (⌃⌥Space unless changed) shares the screen evenly among all its windows.
    @Published var arrangesAll: Bool {
        didSet { defaults.set(arrangesAll, forKey: Keys.arrangesAll) }
    }

    /// Keys chosen for the shortcuts, by id (`SnapKeys.ids`); missing ones keep their default.
    @Published var keyCodes: [String: UInt32] {
        didSet { defaults.set(keyCodes.mapValues { NSNumber(value: $0) }, forKey: Keys.keyCodes) }
    }

    func keyCode(for id: String) -> UInt32 {
        keyCodes[id] ?? SnapKeys.defaultCode(for: id)
    }

    func shortcut(for id: String) -> Shortcut {
        SnapKeys.shortcut(code: keyCode(for: id))
    }

    /// The drag areas that snap.
    @Published var gestures: Set<SnapGesture> {
        didSet { defaults.set(gestures.map(\.rawValue), forKey: Keys.gestures) }
    }


    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            Keys.isEnabled: false,
            Keys.snapsByDragging: true,
            Keys.resizesTogether: true,
            Keys.fillsSpace: true,
            Keys.edgeArea: Self.defaultEdgeArea,
            Keys.gestures: SnapGesture.defaults.map(\.rawValue),
            Keys.arrangesAll: true,
        ])
        isEnabled = defaults.bool(forKey: Keys.isEnabled)
        snapsByDragging = defaults.bool(forKey: Keys.snapsByDragging)
        resizesTogether = defaults.bool(forKey: Keys.resizesTogether)
        fillsSpace = defaults.bool(forKey: Keys.fillsSpace)
        edgeArea = defaults.double(forKey: Keys.edgeArea)
        gestures = Set((defaults.stringArray(forKey: Keys.gestures) ?? []).compactMap(SnapGesture.init(rawValue:)))
        arrangesAll = defaults.bool(forKey: Keys.arrangesAll)
        keyCodes = (defaults.dictionary(forKey: Keys.keyCodes) as? [String: NSNumber] ?? [:]).mapValues(\.uint32Value)
    }

    /// Back to how dragging, resizing, gestures, Arrange All and the shortcut keys start out; the
    /// on/off switch stays.
    func reset() {
        arrangesAll = true
        keyCodes = [:]
        snapsByDragging = true
        resizesTogether = true
        fillsSpace = true
        edgeArea = Self.defaultEdgeArea
        gestures = SnapGesture.defaults
    }

    private enum Keys {
        static let isEnabled = "windowSnappingEnabled"
        static let snapsByDragging = "windowSnappingByDragging"
        static let resizesTogether = "windowSnappingResizesTogether"
        static let edgeArea = "windowSnappingEdgeArea"
        static let fillsSpace = "windowSnappingFillsSpace"
        static let gestures = "windowSnappingGestures"
        static let arrangesAll = "windowSnappingArrangesAll"
        static let keyCodes = "windowSnappingKeyCodes"
    }
}
