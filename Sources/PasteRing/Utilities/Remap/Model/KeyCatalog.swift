import CoreGraphics

/// A key, by the HID usage the keyboard sends and the macOS key code it becomes.
struct KeyInfo {
    enum Section: String, CaseIterable {
        case letters = "Letters"
        case numbers = "Numbers"
        case modifiers = "Modifiers"
        case editing = "Editing"
        case navigation = "Navigation"
        case function = "Function Keys"
        case symbols = "Symbols"
        case keypad = "Keypad"
        case other = "Other"

        var title: String { localized(rawValue) }
    }

    /// Usage page in the upper 32 bits, usage in the lower, as key mappings take it.
    let usage: UInt64
    /// Nil for keys macOS has no key code for; they can only be remapped to other keys.
    let keyCode: CGKeyCode?
    let name: String
    let section: Section
}

/// Every key PasteRing can remap from or to.
enum KeyCatalog {
    static let keyboardPage: UInt64 = 0x07 << 32
    /// Apple's fn key lives on a vendor page.
    static let fnUsage: UInt64 = 0xFF << 32 | 0x03

    static let all: [KeyInfo] = {
        var keys: [KeyInfo] = []
        func add(_ usage: UInt64, _ keyCode: CGKeyCode?, _ name: String, _ section: KeyInfo.Section) {
            keys.append(KeyInfo(usage: usage > 0xFFFF ? usage : KeyCatalog.keyboardPage | usage, keyCode: keyCode, name: name, section: section))
        }
        let letterCodes: [CGKeyCode] = [0x00, 0x0B, 0x08, 0x02, 0x0E, 0x03, 0x05, 0x04, 0x22, 0x26, 0x28, 0x25, 0x2E,
                                        0x2D, 0x1F, 0x23, 0x0C, 0x0F, 0x01, 0x11, 0x20, 0x09, 0x0D, 0x07, 0x10, 0x06]
        for (index, code) in letterCodes.enumerated() {
            add(0x04 + UInt64(index), code, String(UnicodeScalar(UInt8(65 + index))), .letters)
        }
        let numberCodes: [CGKeyCode] = [0x12, 0x13, 0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C, 0x19, 0x1D]
        for (index, code) in numberCodes.enumerated() {
            add(0x1E + UInt64(index), code, "\((index + 1) % 10)", .numbers)
        }

        add(0xE3, 0x37, String(localized: "Left Command"), .modifiers)
        add(0xE7, 0x36, String(localized: "Right Command"), .modifiers)
        add(0xE2, 0x3A, String(localized: "Left Option"), .modifiers)
        add(0xE6, 0x3D, String(localized: "Right Option"), .modifiers)
        add(0xE0, 0x3B, String(localized: "Left Control"), .modifiers)
        add(0xE4, 0x3E, String(localized: "Right Control"), .modifiers)
        add(0xE1, 0x38, String(localized: "Left Shift"), .modifiers)
        add(0xE5, 0x3C, String(localized: "Right Shift"), .modifiers)
        add(0x39, 0x39, String(localized: "Caps Lock"), .modifiers)
        add(KeyCatalog.fnUsage, 0x3F, "fn", .modifiers)

        add(0x28, 0x24, String(localized: "Return"), .editing)
        add(0x2B, 0x30, String(localized: "Tab"), .editing)
        add(0x2C, 0x31, String(localized: "Space"), .editing)
        add(0x2A, 0x33, String(localized: "Delete"), .editing)
        add(0x4C, 0x75, String(localized: "Forward Delete"), .editing)
        add(0x29, 0x35, String(localized: "Escape"), .editing)
        add(0x49, 0x72, String(localized: "Insert"), .editing)

        add(0x52, 0x7E, String(localized: "Up Arrow"), .navigation)
        add(0x51, 0x7D, String(localized: "Down Arrow"), .navigation)
        add(0x50, 0x7B, String(localized: "Left Arrow"), .navigation)
        add(0x4F, 0x7C, String(localized: "Right Arrow"), .navigation)
        add(0x4A, 0x73, String(localized: "Home"), .navigation)
        add(0x4D, 0x77, String(localized: "End"), .navigation)
        add(0x4B, 0x74, String(localized: "Page Up"), .navigation)
        add(0x4E, 0x79, String(localized: "Page Down"), .navigation)

        let functionCodes: [CGKeyCode?] = [0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D, 0x67, 0x6F]
        for (index, code) in functionCodes.enumerated() {
            add(0x3A + UInt64(index), code, "F\(index + 1)", .function)
        }
        let highFunctionCodes: [CGKeyCode?] = [0x69, 0x6B, 0x71, 0x6A, 0x40, 0x4F, 0x50, 0x5A, nil, nil, nil, nil]
        for (index, code) in highFunctionCodes.enumerated() {
            add(0x68 + UInt64(index), code, "F\(index + 13)", .function)
        }

        add(0x2D, 0x1B, String(localized: "- (Minus)"), .symbols)
        add(0x2E, 0x18, String(localized: "= (Equals)"), .symbols)
        add(0x2F, 0x21, String(localized: "[ (Left Bracket)"), .symbols)
        add(0x30, 0x1E, String(localized: "] (Right Bracket)"), .symbols)
        add(0x31, 0x2A, String(localized: "\\ (Backslash)"), .symbols)
        add(0x33, 0x29, String(localized: "; (Semicolon)"), .symbols)
        add(0x34, 0x27, String(localized: "' (Quote)"), .symbols)
        add(0x35, 0x32, String(localized: "` (Grave Accent)"), .symbols)
        add(0x36, 0x2B, String(localized: ", (Comma)"), .symbols)
        add(0x37, 0x2F, String(localized: ". (Period)"), .symbols)
        add(0x38, 0x2C, String(localized: "/ (Slash)"), .symbols)
        add(0x64, 0x0A, String(localized: "§ (Section)"), .symbols)

        let keypadCodes: [CGKeyCode] = [0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5B, 0x5C]
        for (index, code) in keypadCodes.enumerated() {
            add(0x59 + UInt64(index), code, keypad("\(index + 1)"), .keypad)
        }
        add(0x62, 0x52, keypad("0"), .keypad)
        add(0x63, 0x41, keypad("."), .keypad)
        add(0x58, 0x4C, String(localized: "Keypad Enter"), .keypad)
        add(0x57, 0x45, keypad("+"), .keypad)
        add(0x56, 0x4E, keypad("-"), .keypad)
        add(0x55, 0x43, keypad("*"), .keypad)
        add(0x54, 0x4B, keypad("/"), .keypad)
        add(0x67, 0x51, keypad("="), .keypad)
        add(0x53, 0x47, String(localized: "Keypad Clear"), .keypad)

        add(0x46, nil, String(localized: "Print Screen"), .other)
        add(0x47, nil, String(localized: "Scroll Lock"), .other)
        add(0x48, nil, String(localized: "Pause"), .other)
        add(0x65, 0x6E, String(localized: "Menu"), .other)
        add(0x7F, 0x4A, String(localized: "Mute"), .other)
        add(0x80, 0x48, String(localized: "Volume Up"), .other)
        add(0x81, 0x49, String(localized: "Volume Down"), .other)
        return keys
    }()

    /// "Keypad 1", "Keypad +" and so on, in the app's language.
    private static func keypad(_ label: String) -> String {
        String(localized: "Keypad \(label)")
    }

    private static let byUsage = Dictionary(KeyCatalog.all.map { ($0.usage, $0) }, uniquingKeysWith: { first, _ in first })
    private static let byKeyCode = Dictionary(KeyCatalog.all.compactMap { key in key.keyCode.map { ($0, key) } }, uniquingKeysWith: { first, _ in first })

    static func key(usage: UInt64) -> KeyInfo? { byUsage[usage] }
    static func key(keyCode: CGKeyCode) -> KeyInfo? { byKeyCode[keyCode] }

    /// A readable name for any key, listed or not.
    static func name(usage: UInt64) -> String {
        key(usage: usage)?.name ?? String(localized: "Key \(String(format: "0x%llX", usage))")
    }

    /// The device-specific flag each modifier key sets while held, telling left from right.
    static func modifierFlag(keyCode: CGKeyCode) -> UInt64? {
        switch keyCode {
        case 0x3B: 0x0000_0001 // left control
        case 0x38: 0x0000_0002 // left shift
        case 0x3C: 0x0000_0004 // right shift
        case 0x37: 0x0000_0008 // left command
        case 0x36: 0x0000_0010 // right command
        case 0x3A: 0x0000_0020 // left option
        case 0x3D: 0x0000_0040 // right option
        case 0x3E: 0x0000_2000 // right control
        case 0x39: CGEventFlags.maskAlphaShift.rawValue
        case 0x3F: CGEventFlags.maskSecondaryFn.rawValue
        default: nil
        }
    }
}

/// Names for mouse buttons, by the number macOS gives them (0 is the left button).
enum MouseButtons {
    static func name(_ number: Int) -> String {
        switch number {
        case 0: String(localized: "Left Button")
        case 1: String(localized: "Right Button")
        case 2: String(localized: "Middle Button")
        case 3: String(localized: "Button 4 (Back)")
        case 4: String(localized: "Button 5 (Forward)")
        default: String(localized: "Button \(number + 1)")
        }
    }

    /// Buttons offered to remap from: everything but the left button, so the mouse can
    /// always click.
    static let remappable = Array(1...9)
}
