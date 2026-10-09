import Foundation

/// How many fingers tap the trackpad for a middle click.
enum TapFingers: Int, CaseIterable, Identifiable {
    case three = 3
    case four = 4

    var id: Self { self }

    var title: String {
        switch self {
        case .three: "Three fingers"
        case .four: "Four fingers"
        }
    }
}

/// Middle Click preferences, persisted in UserDefaults.
@MainActor
final class MiddleClickSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.isEnabled) }
    }

    @Published var fingers: TapFingers {
        didSet { defaults.set(fingers.rawValue, forKey: Keys.fingers) }
    }

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [Keys.isEnabled: false, Keys.fingers: TapFingers.three.rawValue])
        isEnabled = defaults.bool(forKey: Keys.isEnabled)
        fingers = TapFingers(rawValue: defaults.integer(forKey: Keys.fingers)) ?? .three
    }

    private enum Keys {
        static let isEnabled = "middleClickEnabled"
        static let fingers = "middleClickFingers"
    }
}
