import Foundation

/// Delete to Trash preferences, persisted in UserDefaults.
@MainActor
final class DeleteToTrashSettings: ObservableObject {
    static let defaultUsesDelete = true
    static let defaultUsesForwardDelete = true
    static let defaultShiftDeletesImmediately = true

    private let defaults = UserDefaults.standard

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.isEnabled) }
    }

    /// Whether Delete (⌫: the Mac keyboard's delete key, Backspace on others) deletes.
    @Published var usesDelete: Bool {
        didSet { defaults.set(usesDelete, forKey: Keys.usesDelete) }
    }

    /// Whether Forward Delete (⌦: Delete on keyboards made for Windows, fn-Delete on a Mac
    /// keyboard) deletes.
    @Published var usesForwardDelete: Bool {
        didSet { defaults.set(usesForwardDelete, forKey: Keys.usesForwardDelete) }
    }

    /// Whether Shift with either key deletes without going to the Trash, where the app can.
    @Published var shiftDeletesImmediately: Bool {
        didSet { defaults.set(shiftDeletesImmediately, forKey: Keys.shiftDeletesImmediately) }
    }

    /// Bundle identifiers of apps where the keys are left as they are.
    @Published var excludedApps: Set<String> {
        didSet { defaults.set(Array(excludedApps), forKey: Keys.excludedApps) }
    }

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            Keys.isEnabled: false,
            Keys.usesDelete: Self.defaultUsesDelete,
            Keys.usesForwardDelete: Self.defaultUsesForwardDelete,
            Keys.shiftDeletesImmediately: Self.defaultShiftDeletesImmediately,
        ])
        isEnabled = defaults.bool(forKey: Keys.isEnabled)
        usesDelete = defaults.bool(forKey: Keys.usesDelete)
        usesForwardDelete = defaults.bool(forKey: Keys.usesForwardDelete)
        shiftDeletesImmediately = defaults.bool(forKey: Keys.shiftDeletesImmediately)
        excludedApps = Set(defaults.stringArray(forKey: Keys.excludedApps) ?? [])
    }

    /// Back to both keys deleting, and Shift deleting immediately; the on/off switch and
    /// excluded apps stay as they are.
    func reset() {
        usesDelete = Self.defaultUsesDelete
        usesForwardDelete = Self.defaultUsesForwardDelete
        shiftDeletesImmediately = Self.defaultShiftDeletesImmediately
    }

    private enum Keys {
        static let isEnabled = "deleteToTrashEnabled"
        static let usesDelete = "deleteToTrashDelete"
        static let usesForwardDelete = "deleteToTrashForwardDelete"
        static let shiftDeletesImmediately = "deleteToTrashShiftImmediately"
        static let excludedApps = "deleteToTrashExcludedApps"
    }
}
