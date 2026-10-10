import Foundation
import SwiftUI
import Carbon.HIToolbox

/// Order here is the order shown in Settings.
enum OverlayStyle: String, CaseIterable, Identifiable {
    case simple
    case grid
    case carousel
    case stack
    case ring

    var id: Self { self }

    var title: String {
        switch self {
        case .simple: String(localized: "Default")
        case .stack: String(localized: "Stack")
        case .carousel: String(localized: "Carousel")
        case .grid: String(localized: "Grid")
        case .ring: String(localized: "Ring menu")
        }
    }
}

/// How long entries stay in the history.
enum HistoryExpiry: String, CaseIterable, Identifiable {
    case never
    case hour
    case day
    case week
    case month

    var id: Self { self }

    var title: String {
        switch self {
        case .never: String(localized: "Never")
        case .hour: String(localized: "After 1 hour")
        case .day: String(localized: "After 1 day")
        case .week: String(localized: "After 1 week")
        case .month: String(localized: "After 30 days")
        }
    }

    var interval: TimeInterval? {
        switch self {
        case .never: nil
        case .hour: 3600
        case .day: 86_400
        case .week: 7 * 86_400
        case .month: 30 * 86_400
        }
    }
}

/// User preferences, persisted in UserDefaults.
@MainActor
final class ClipboardSettings: ObservableObject {
    static let maxItemsRange = 5...100
    static let ringSizeRange = 3...24
    static let gridColumns = GridLayout.columns
    static let gridSizeRange = 8...24
    static let simpleWidthRange: ClosedRange<Double> = 360...900
    static let simpleHeightRange: ClosedRange<Double> = 120...420
    static let gridCardWidthRange: ClosedRange<Double> = 200...480
    static let gridCardHeightRange: ClosedRange<Double> = 160...560
    static let carouselSizeRange: ClosedRange<Double> = 180...420
    static let stackWidthRange: ClosedRange<Double> = 360...800
    static let stackHeightRange: ClosedRange<Double> = 120...360
    static let ringChipWidthRange: ClosedRange<Double> = 160...480
    static let ringChipHeightRange: ClosedRange<Double> = 80...480

    /// What each setting is at first, for Reset to Defaults and each row's Reset to Default.
    enum Default {
        static let isEnabled = true
        static let maxItems = 50
        static let ignorePasswords = true
        static let recordImages = true
        static let pasteAsPlainText = false
        static let removeDuplicates = true
        static let moveToTopOnPaste = true
        static let expiry = HistoryExpiry.never
        static let style = OverlayStyle.simple
        static let ringSize = 16
        static let gridSize = 12
        static let gridCardWidth = 320.0
        static let gridCardHeight = 256.0
        static let simpleWidth = 560.0
        static let simpleHeight = 256.0
        static let carouselWidth = 260.0
        static let carouselHeight = 260.0
        static let stackWidth = 520.0
        static let stackHeight = 256.0
        static let ringChipWidth = 280.0
        static let ringChipHeight = 256.0
        static let showCopyDate = true
        static let showDeleteButton = true
    }

    private let defaults = UserDefaults.standard

    /// The whole utility: recording, the overlay and its shortcuts.
    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.isEnabled) }
    }

    @Published var maxItems: Int {
        didSet { defaults.set(maxItems, forKey: Keys.maxItems) }
    }

    /// Skip text copied from password fields and password managers.
    @Published var ignorePasswords: Bool {
        didSet { defaults.set(ignorePasswords, forKey: Keys.ignorePasswords) }
    }

    /// Record copied images. Text, rich text and files are always recorded.
    @Published var recordImages: Bool {
        didSet { defaults.set(recordImages, forKey: Keys.recordImages) }
    }

    /// Paste rich text without its formatting, so it takes the style of where it is pasted.
    @Published var pasteAsPlainText: Bool {
        didSet { defaults.set(pasteAsPlainText, forKey: Keys.pasteAsPlainText) }
    }

    /// Copying something already in the history moves it to the top instead of adding it again.
    @Published var removeDuplicates: Bool {
        didSet { defaults.set(removeDuplicates, forKey: Keys.removeDuplicates) }
    }

    /// Pasting an entry from the overlay makes it the most recent one. When off, the history
    /// keeps copy order and ⌘V goes back to the last copied text after the paste.
    @Published var moveToTopOnPaste: Bool {
        didSet { defaults.set(moveToTopOnPaste, forKey: Keys.moveToTopOnPaste) }
    }

    @Published var expiry: HistoryExpiry {
        didSet { defaults.set(expiry.rawValue, forKey: Keys.expiry) }
    }

    /// Bundle identifiers of apps whose copies are not recorded.
    @Published var excludedApps: Set<String> {
        didSet { defaults.set(Array(excludedApps), forKey: Keys.excludedApps) }
    }

    /// Shortcuts that open the overlay. Always at least one.
    @Published var shortcuts: [Shortcut] {
        didSet { defaults.set(try? JSONEncoder().encode(shortcuts), forKey: Keys.shortcuts) }
    }

    @Published var showCopyDate: Bool {
        didSet { defaults.set(showCopyDate, forKey: Keys.showCopyDate) }
    }

    @Published var showDeleteButton: Bool {
        didSet { defaults.set(showDeleteButton, forKey: Keys.showDeleteButton) }
    }

    /// How many of the most recent entries the ring menu shows. All of them fit on the circle.
    @Published var ringSize: Int {
        didSet { defaults.set(ringSize, forKey: Keys.ringSize) }
    }

    /// How many of the most recent entries the grid shows, all at once. A multiple of the columns.
    @Published var gridSize: Int {
        didSet { defaults.set(gridSize, forKey: Keys.gridSize) }
    }

    @Published var gridCardWidth: Double {
        didSet { defaults.set(gridCardWidth, forKey: Keys.gridCardWidth) }
    }

    @Published var gridCardHeight: Double {
        didSet { defaults.set(gridCardHeight, forKey: Keys.gridCardHeight) }
    }

    @Published var carouselWidth: Double {
        didSet { defaults.set(carouselWidth, forKey: Keys.carouselWidth) }
    }

    @Published var carouselHeight: Double {
        didSet { defaults.set(carouselHeight, forKey: Keys.carouselHeight) }
    }

    @Published var stackWidth: Double {
        didSet { defaults.set(stackWidth, forKey: Keys.stackWidth) }
    }

    @Published var stackHeight: Double {
        didSet { defaults.set(stackHeight, forKey: Keys.stackHeight) }
    }

    @Published var ringChipWidth: Double {
        didSet { defaults.set(ringChipWidth, forKey: Keys.ringChipWidth) }
    }

    @Published var ringChipHeight: Double {
        didSet { defaults.set(ringChipHeight, forKey: Keys.ringChipHeight) }
    }

    @Published var simpleWidth: Double {
        didSet { defaults.set(simpleWidth, forKey: Keys.simpleWidth) }
    }

    @Published var simpleHeight: Double {
        didSet { defaults.set(simpleHeight, forKey: Keys.simpleHeight) }
    }

    @Published var style: OverlayStyle {
        didSet { defaults.set(style.rawValue, forKey: Keys.style) }
    }

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            Keys.isEnabled: Default.isEnabled,
            Keys.maxItems: Default.maxItems,
            Keys.ignorePasswords: Default.ignorePasswords,
            Keys.recordImages: Default.recordImages,
            Keys.pasteAsPlainText: Default.pasteAsPlainText,
            Keys.removeDuplicates: Default.removeDuplicates,
            Keys.moveToTopOnPaste: Default.moveToTopOnPaste,
        ])
        defaults.register(defaults: Self.appearanceDefaults)
        isEnabled = defaults.bool(forKey: Keys.isEnabled)
        maxItems = defaults.integer(forKey: Keys.maxItems)
        ignorePasswords = defaults.bool(forKey: Keys.ignorePasswords)
        recordImages = defaults.bool(forKey: Keys.recordImages)
        pasteAsPlainText = defaults.bool(forKey: Keys.pasteAsPlainText)
        removeDuplicates = defaults.bool(forKey: Keys.removeDuplicates)
        moveToTopOnPaste = defaults.bool(forKey: Keys.moveToTopOnPaste)
        let savedShortcuts = defaults.data(forKey: Keys.shortcuts).flatMap { try? JSONDecoder().decode([Shortcut].self, from: $0) }
        shortcuts = savedShortcuts?.isEmpty == false ? savedShortcuts! : [Self.defaultShortcut]
        showCopyDate = defaults.bool(forKey: Keys.showCopyDate)
        showDeleteButton = defaults.bool(forKey: Keys.showDeleteButton)
        expiry = HistoryExpiry(rawValue: defaults.string(forKey: Keys.expiry) ?? "") ?? Default.expiry
        excludedApps = Set(defaults.stringArray(forKey: Keys.excludedApps) ?? [])
        ringSize = defaults.integer(forKey: Keys.ringSize)
        gridSize = defaults.integer(forKey: Keys.gridSize)
        gridCardWidth = defaults.double(forKey: Keys.gridCardWidth)
        gridCardHeight = defaults.double(forKey: Keys.gridCardHeight)
        simpleWidth = defaults.double(forKey: Keys.simpleWidth)
        simpleHeight = defaults.double(forKey: Keys.simpleHeight)
        carouselWidth = defaults.double(forKey: Keys.carouselWidth)
        carouselHeight = defaults.double(forKey: Keys.carouselHeight)
        stackWidth = defaults.double(forKey: Keys.stackWidth)
        stackHeight = defaults.double(forKey: Keys.stackHeight)
        ringChipWidth = defaults.double(forKey: Keys.ringChipWidth)
        ringChipHeight = defaults.double(forKey: Keys.ringChipHeight)
        style = OverlayStyle(rawValue: defaults.string(forKey: Keys.style) ?? "") ?? .simple
    }

    /// How many entries the overlay shows for the current style.
    var visibleLimit: Int? {
        switch style {
        case .ring: ringSize
        case .grid: gridSize
        case .simple, .stack, .carousel: nil
        }
    }

    /// Defaults for the settings shown in the Appearance tab. Add new ones here so
    /// Reset to Defaults covers them.
    private static let appearanceDefaults: [String: Any] = [
        Keys.style: Default.style.rawValue,
        Keys.ringSize: Default.ringSize,
        Keys.gridSize: Default.gridSize,
        Keys.gridCardWidth: Default.gridCardWidth,
        Keys.gridCardHeight: Default.gridCardHeight,
        Keys.simpleWidth: Default.simpleWidth,
        Keys.simpleHeight: Default.simpleHeight,
        Keys.carouselWidth: Default.carouselWidth,
        Keys.carouselHeight: Default.carouselHeight,
        Keys.stackWidth: Default.stackWidth,
        Keys.stackHeight: Default.stackHeight,
        Keys.ringChipWidth: Default.ringChipWidth,
        Keys.ringChipHeight: Default.ringChipHeight,
        Keys.showCopyDate: Default.showCopyDate,
        Keys.showDeleteButton: Default.showDeleteButton,
    ]

    /// Back to the default settings, appearance and shortcut; the on/off switch, excluded
    /// apps and history stay as they are.
    func reset() {
        maxItems = Default.maxItems
        ignorePasswords = Default.ignorePasswords
        recordImages = Default.recordImages
        pasteAsPlainText = Default.pasteAsPlainText
        removeDuplicates = Default.removeDuplicates
        moveToTopOnPaste = Default.moveToTopOnPaste
        expiry = Default.expiry
        shortcuts = [Self.defaultShortcut]
        resetAppearance()
    }

    func resetAppearance() {
        for key in Self.appearanceDefaults.keys {
            defaults.removeObject(forKey: key)
        }
        style = OverlayStyle(rawValue: defaults.string(forKey: Keys.style) ?? "") ?? .simple
        ringSize = defaults.integer(forKey: Keys.ringSize)
        gridSize = defaults.integer(forKey: Keys.gridSize)
        gridCardWidth = defaults.double(forKey: Keys.gridCardWidth)
        gridCardHeight = defaults.double(forKey: Keys.gridCardHeight)
        simpleWidth = defaults.double(forKey: Keys.simpleWidth)
        simpleHeight = defaults.double(forKey: Keys.simpleHeight)
        carouselWidth = defaults.double(forKey: Keys.carouselWidth)
        carouselHeight = defaults.double(forKey: Keys.carouselHeight)
        stackWidth = defaults.double(forKey: Keys.stackWidth)
        stackHeight = defaults.double(forKey: Keys.stackHeight)
        ringChipWidth = defaults.double(forKey: Keys.ringChipWidth)
        ringChipHeight = defaults.double(forKey: Keys.ringChipHeight)
        showCopyDate = defaults.bool(forKey: Keys.showCopyDate)
        showDeleteButton = defaults.bool(forKey: Keys.showDeleteButton)
    }

    static let defaultShortcut = Shortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | shiftKey), keyLabel: "V")

    /// The first shortcut back to ⇧⌘V; an alternative already using it is dropped.
    func resetMainShortcut() {
        var rest = Array(shortcuts.dropFirst())
        rest.removeAll { $0.id == Self.defaultShortcut.id }
        shortcuts = [Self.defaultShortcut] + rest
    }

    /// Adds another shortcut, starting from one not in use; the user then records over it.
    func addAlternativeShortcut() {
        let candidates = [
            Shortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | optionKey), keyLabel: "V"),
            Shortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(controlKey | shiftKey), keyLabel: "V"),
            Shortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | controlKey), keyLabel: "V"),
            Shortcut(keyCode: UInt32(kVK_ANSI_B), modifiers: UInt32(cmdKey | shiftKey), keyLabel: "B"),
        ]
        if let unused = candidates.first(where: { !shortcuts.contains($0) }) {
            shortcuts.append(unused)
        }
    }

    /// Binding for one shortcut; ignores a change that would duplicate another one.
    func shortcutBinding(_ shortcut: Shortcut) -> Binding<Shortcut> {
        Binding(
            get: { self.shortcuts.first { $0.id == shortcut.id } ?? shortcut },
            set: { new in
                guard let index = self.shortcuts.firstIndex(where: { $0.id == shortcut.id }),
                      !self.shortcuts.contains(where: { $0.id == new.id && $0.id != shortcut.id })
                else { return }
                self.shortcuts[index] = new
            }
        )
    }

    /// Binding that keeps typed or stepped values inside `range`.
    func clamped(_ keyPath: ReferenceWritableKeyPath<ClipboardSettings, Int>, to range: ClosedRange<Int>) -> Binding<Int> {
        Binding(
            get: { self[keyPath: keyPath] },
            set: { self[keyPath: keyPath] = min(max($0, range.lowerBound), range.upperBound) }
        )
    }

    private enum Keys {
        static let isEnabled = "clipboardManagerEnabled"
        static let maxItems = "maxItems"
        static let ignorePasswords = "ignorePasswords"
        static let recordImages = "recordImages"
        static let pasteAsPlainText = "pasteAsPlainText"
        static let removeDuplicates = "removeDuplicates"
        static let moveToTopOnPaste = "moveToTopOnPaste"
        static let shortcuts = "shortcuts"
        static let showCopyDate = "showCopyDate"
        static let showDeleteButton = "showDeleteButton"
        static let expiry = "historyExpiry"
        static let excludedApps = "excludedApps"
        static let ringSize = "ringSize"
        static let gridSize = "gridSize"
        static let gridCardWidth = "gridCardWidth"
        static let gridCardHeight = "gridCardHeight"
        static let simpleWidth = "simpleWidth"
        static let simpleHeight = "simpleHeight"
        static let carouselWidth = "carouselWidth"
        static let carouselHeight = "carouselHeight"
        static let stackWidth = "stackWidth"
        static let stackHeight = "stackHeight"
        static let ringChipWidth = "ringChipWidth"
        static let ringChipHeight = "ringChipHeight"
        static let style = "overlayStyle"
    }
}
