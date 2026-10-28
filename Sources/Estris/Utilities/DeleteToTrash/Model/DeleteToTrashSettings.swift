import Foundation

/// Delete to Trash preferences, persisted in UserDefaults.
@MainActor
final class DeleteToTrashSettings: ObservableObject {
    static let defaultUsesForwardDelete = true

    private let defaults = UserDefaults.standard

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.isEnabled) }
    }

    /// Whether Forward Delete (⌦, fn-Delete on a laptop) moves items to the Trash too.
    @Published var usesForwardDelete: Bool {
        didSet { defaults.set(usesForwardDelete, forKey: Keys.usesForwardDelete) }
    }

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [Keys.isEnabled: false, Keys.usesForwardDelete: Self.defaultUsesForwardDelete])
        isEnabled = defaults.bool(forKey: Keys.isEnabled)
        usesForwardDelete = defaults.bool(forKey: Keys.usesForwardDelete)
    }

    /// Back to both keys moving items to the Trash; the on/off switch stays.
    func reset() {
        usesForwardDelete = Self.defaultUsesForwardDelete
    }

    private enum Keys {
        static let isEnabled = "deleteToTrashEnabled"
        static let usesForwardDelete = "deleteToTrashForwardDelete"
    }
}
