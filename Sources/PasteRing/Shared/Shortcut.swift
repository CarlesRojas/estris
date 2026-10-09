import AppKit
import Carbon.HIToolbox

/// A global keyboard shortcut: a key plus Carbon modifier flags.
struct Shortcut: Codable, Hashable, Identifiable {
    var keyCode: UInt32
    var modifiers: UInt32
    /// What the key shows as, captured when it was recorded (keyboard layouts differ).
    var keyLabel: String

    var id: String { "\(keyCode)-\(modifiers)" }

    var displayString: String {
        modifierSymbols + keyLabel
    }

    /// The modifiers alone, in the standard order, such as "⇧⌘".
    var modifierSymbols: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text
    }

    /// The same modifiers as AppKit flags, for checking which keys are held.
    var modifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        return flags
    }

    /// Builds a shortcut from a key press. Needs ⌘, ⌥ or ⌃, so it can't swallow typing,
    /// and so there is a modifier to release.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.isDisjoint(with: [.command, .option, .control]),
              let label = Self.label(for: event)
        else { return nil }
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        self.init(keyCode: UInt32(event.keyCode), modifiers: modifiers, keyLabel: label)
    }

    init(keyCode: UInt32, modifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    private static let specialKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    private static func label(for event: NSEvent) -> String? {
        if event.keyCode == UInt16(kVK_Escape) { return nil }
        if let special = specialKeys[Int(event.keyCode)] { return special }
        guard let characters = event.charactersIgnoringModifiers?.uppercased(),
              !characters.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return characters
    }
}
