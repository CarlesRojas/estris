import Foundation

/// Which trackpad tap, if any, clicks the middle button.
enum MiddleClickGesture: String, CaseIterable, Identifiable {
    case off
    case threeFingerTap
    case fourFingerTap

    var id: Self { self }

    var title: String {
        switch self {
        case .off: "Off"
        case .threeFingerTap: "Tap with three fingers"
        case .fourFingerTap: "Tap with four fingers"
        }
    }

    /// Fingers in the tap; 0 when off.
    var fingers: Int {
        switch self {
        case .off: 0
        case .threeFingerTap: 3
        case .fourFingerTap: 4
        }
    }
}

/// Mouse preferences, persisted in UserDefaults.
@MainActor
final class MouseSettings: ObservableObject {
    /// Slowest and fastest pointer speed offered. System Settings stops at 3.
    static let speedRange: ClosedRange<Double> = 0...5

    private let defaults = UserDefaults.standard

    @Published var middleClick: MiddleClickGesture {
        didSet { defaults.set(middleClick.rawValue, forKey: Keys.middleClick) }
    }

    /// Whether PasteRing sets the speed; when off, the System Settings speed is used.
    @Published var setsMouseSpeed: Bool {
        didSet { defaults.set(setsMouseSpeed, forKey: Keys.setsMouseSpeed) }
    }

    @Published var mouseSpeed: Double {
        didSet { defaults.set(mouseSpeed, forKey: Keys.mouseSpeed) }
    }

    @Published var setsTrackpadSpeed: Bool {
        didSet { defaults.set(setsTrackpadSpeed, forKey: Keys.setsTrackpadSpeed) }
    }

    @Published var trackpadSpeed: Double {
        didSet { defaults.set(trackpadSpeed, forKey: Keys.trackpadSpeed) }
    }

    init() {
        let defaults = UserDefaults.standard
        // Speeds start from what System Settings has, so turning one on changes nothing yet.
        defaults.register(defaults: [
            Keys.middleClick: MiddleClickGesture.off.rawValue,
            Keys.mouseSpeed: PointerSpeed.systemSpeed(of: .mouse),
            Keys.trackpadSpeed: PointerSpeed.systemSpeed(of: .trackpad),
        ])
        middleClick = MiddleClickGesture(rawValue: defaults.string(forKey: Keys.middleClick) ?? "") ?? .off
        setsMouseSpeed = defaults.bool(forKey: Keys.setsMouseSpeed)
        mouseSpeed = defaults.double(forKey: Keys.mouseSpeed)
        setsTrackpadSpeed = defaults.bool(forKey: Keys.setsTrackpadSpeed)
        trackpadSpeed = defaults.double(forKey: Keys.trackpadSpeed)
    }

    private enum Keys {
        static let middleClick = "mouseMiddleClick"
        static let setsMouseSpeed = "mouseSetsMouseSpeed"
        static let mouseSpeed = "mouseMouseSpeed"
        static let setsTrackpadSpeed = "mouseSetsTrackpadSpeed"
        static let trackpadSpeed = "mouseTrackpadSpeed"
    }
}
