import Foundation

/// Dock Preview preferences, persisted in UserDefaults.
@MainActor
final class DockPreviewSettings: ObservableObject {
    static let defaultSize: Double = 200
    static let defaultCurrentDesktopOnly = false
    static let defaultOpenDelay = HoverDelay.immediately
    static let defaultShowsCloseButton = true
    static let defaultScrollSwitchesWindows = false
    /// The previews' height, in points.
    static let sizes: ClosedRange<Double> = 80...320

    private let defaults = UserDefaults.standard

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.isEnabled) }
    }

    /// Each window's preview height; the width follows the window's shape.
    @Published var size: Double {
        didSet { defaults.set(size, forKey: Keys.size) }
    }

    /// Only windows on the desktop (Space) in use.
    @Published var currentDesktopOnly: Bool {
        didSet { defaults.set(currentDesktopOnly, forKey: Keys.currentDesktopOnly) }
    }

    /// How long the pointer stays on a Dock icon before its windows show.
    @Published var openDelay: HoverDelay {
        didSet { defaults.set(openDelay.rawValue, forKey: Keys.openDelay) }
    }

    /// While the panel shows, the scroll wheel brings one window after another forward.
    @Published var scrollSwitchesWindows: Bool {
        didSet { defaults.set(scrollSwitchesWindows, forKey: Keys.scrollSwitchesWindows) }
    }

    /// A × on each preview that closes its window.
    @Published var showsCloseButton: Bool {
        didSet { defaults.set(showsCloseButton, forKey: Keys.showsCloseButton) }
    }

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            Keys.size: Self.defaultSize,
            Keys.currentDesktopOnly: Self.defaultCurrentDesktopOnly,
            Keys.openDelay: Self.defaultOpenDelay.rawValue,
            Keys.showsCloseButton: Self.defaultShowsCloseButton,
            Keys.scrollSwitchesWindows: Self.defaultScrollSwitchesWindows,
        ])
        isEnabled = defaults.bool(forKey: Keys.isEnabled)
        size = min(max(defaults.double(forKey: Keys.size), Self.sizes.lowerBound), Self.sizes.upperBound)
        currentDesktopOnly = defaults.bool(forKey: Keys.currentDesktopOnly)
        openDelay = HoverDelay(rawValue: defaults.integer(forKey: Keys.openDelay)) ?? Self.defaultOpenDelay
        showsCloseButton = defaults.bool(forKey: Keys.showsCloseButton)
        scrollSwitchesWindows = defaults.bool(forKey: Keys.scrollSwitchesWindows)
    }

    /// Back to the default size, delay and switches; the on/off switch stays.
    func reset() {
        size = Self.defaultSize
        currentDesktopOnly = Self.defaultCurrentDesktopOnly
        openDelay = Self.defaultOpenDelay
        showsCloseButton = Self.defaultShowsCloseButton
        scrollSwitchesWindows = Self.defaultScrollSwitchesWindows
    }

    private enum Keys {
        static let isEnabled = "dockPreviewEnabled"
        static let size = "dockPreviewSize"
        static let currentDesktopOnly = "dockPreviewCurrentDesktopOnly"
        static let openDelay = "dockPreviewOpenDelay"
        static let showsCloseButton = "dockPreviewShowsCloseButton"
        static let scrollSwitchesWindows = "dockPreviewScrollSwitchesWindows"
    }
}
