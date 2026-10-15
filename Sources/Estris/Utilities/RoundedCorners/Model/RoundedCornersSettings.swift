import Foundation

/// Rounded Corners preferences, persisted in UserDefaults.
@MainActor
final class RoundedCornersSettings: ObservableObject {
    /// Concentric with a window filling the screen, which touches its edges: the same radius as
    /// macOS's window corners, larger since macOS 26.
    static let defaultRadius: Double = ProcessInfo.processInfo.isOperatingSystemAtLeast(
        OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)
    ) ? 16 : 10
    static let radiusRange: ClosedRange<Double> = 2...40

    private let defaults = UserDefaults.standard

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.isEnabled) }
    }

    /// How round the screen's corners are, in points.
    @Published var radius: Double {
        didSet { defaults.set(radius, forKey: Keys.radius) }
    }

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [Keys.radius: Self.defaultRadius])
        isEnabled = defaults.bool(forKey: Keys.isEnabled)
        radius = defaults.double(forKey: Keys.radius)
    }

    /// Back to the default radius; the on/off switch stays.
    func reset() {
        radius = Self.defaultRadius
    }

    private enum Keys {
        static let isEnabled = "roundedCornersEnabled"
        static let radius = "roundedCornersRadius"
    }
}
