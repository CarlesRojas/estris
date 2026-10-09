import Foundation

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

    /// Shortcut per action; actions left out use their default.
    @Published var shortcuts: [SnapAction: Shortcut] {
        didSet { defaults.set(try? JSONEncoder().encode(shortcuts), forKey: Keys.shortcuts) }
    }

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [Keys.isEnabled: false, Keys.snapsByDragging: true, Keys.resizesTogether: true])
        isEnabled = defaults.bool(forKey: Keys.isEnabled)
        snapsByDragging = defaults.bool(forKey: Keys.snapsByDragging)
        resizesTogether = defaults.bool(forKey: Keys.resizesTogether)
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
    }
}
