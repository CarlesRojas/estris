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
    private let defaults = UserDefaults.standard

    @Published var middleClick: MiddleClickGesture {
        didSet { defaults.set(middleClick.rawValue, forKey: Keys.middleClick) }
    }

    init() {
        middleClick = MiddleClickGesture(rawValue: UserDefaults.standard.string(forKey: Keys.middleClick) ?? "") ?? .off
    }

    private enum Keys {
        static let middleClick = "mouseMiddleClick"
    }
}
