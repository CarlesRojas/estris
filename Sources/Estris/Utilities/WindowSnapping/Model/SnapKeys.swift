import AppKit
import Carbon.HIToolbox

/// A key a Window Snapping shortcut can use, with ⌃⌥.
struct SnapKey: Hashable, Identifiable {
    let code: UInt32
    let label: String

    var id: UInt32 { code }
}

/// The keys to choose from, and which shortcut has which.
enum SnapKeys {
    /// Letters, digits, arrows, Return, Delete, Space, Tab and punctuation. Labels follow a US
    /// layout, by position.
    static let all: [SnapKey] = {
        let letters: [(Int, String)] = [
            (kVK_ANSI_A, "A"), (kVK_ANSI_B, "B"), (kVK_ANSI_C, "C"), (kVK_ANSI_D, "D"), (kVK_ANSI_E, "E"),
            (kVK_ANSI_F, "F"), (kVK_ANSI_G, "G"), (kVK_ANSI_H, "H"), (kVK_ANSI_I, "I"), (kVK_ANSI_J, "J"),
            (kVK_ANSI_K, "K"), (kVK_ANSI_L, "L"), (kVK_ANSI_M, "M"), (kVK_ANSI_N, "N"), (kVK_ANSI_O, "O"),
            (kVK_ANSI_P, "P"), (kVK_ANSI_Q, "Q"), (kVK_ANSI_R, "R"), (kVK_ANSI_S, "S"), (kVK_ANSI_T, "T"),
            (kVK_ANSI_U, "U"), (kVK_ANSI_V, "V"), (kVK_ANSI_W, "W"), (kVK_ANSI_X, "X"), (kVK_ANSI_Y, "Y"),
            (kVK_ANSI_Z, "Z"),
        ]
        let digits: [(Int, String)] = [
            (kVK_ANSI_1, "1"), (kVK_ANSI_2, "2"), (kVK_ANSI_3, "3"), (kVK_ANSI_4, "4"), (kVK_ANSI_5, "5"),
            (kVK_ANSI_6, "6"), (kVK_ANSI_7, "7"), (kVK_ANSI_8, "8"), (kVK_ANSI_9, "9"), (kVK_ANSI_0, "0"),
        ]
        let others: [(Int, String)] = [
            (kVK_LeftArrow, "←"), (kVK_RightArrow, "→"), (kVK_UpArrow, "↑"), (kVK_DownArrow, "↓"),
            (kVK_Return, "↩"), (kVK_Delete, "⌫"), (kVK_Space, String(localized: "Space")), (kVK_Tab, "⇥"),
            (kVK_ANSI_Minus, "-"), (kVK_ANSI_Equal, "="), (kVK_ANSI_LeftBracket, "["), (kVK_ANSI_RightBracket, "]"),
            (kVK_ANSI_Semicolon, ";"), (kVK_ANSI_Quote, "'"), (kVK_ANSI_Comma, ","), (kVK_ANSI_Period, "."),
            (kVK_ANSI_Slash, "/"), (kVK_ANSI_Backslash, "\\"), (kVK_ANSI_Grave, "`"),
        ]
        return (letters + digits + others).map { SnapKey(code: UInt32($0.0), label: $0.1) }
    }()

    static func key(_ code: UInt32) -> SnapKey {
        all.first { $0.code == code } ?? SnapKey(code: code, label: "?")
    }

    /// Arrange All's id among the shortcuts, next to the snap actions' raw values.
    static let arrangeAllID = "arrangeAll"

    /// Each shortcut's key as it starts out.
    static func defaultCode(for id: String) -> UInt32 {
        if id == arrangeAllID { return UInt32(kVK_Space) }
        return SnapAction(rawValue: id)?.defaultKeyCode ?? 0
    }

    /// Every shortcut's id, in priority order, the order the pane shows them in: Arrange All,
    /// then the snap actions. When two share a key, the first one gets it.
    static var ids: [String] {
        [arrangeAllID] + SnapAction.allCases.map(\.rawValue)
    }

    static let modifiers = UInt32(controlKey | optionKey)

    static func shortcut(code: UInt32) -> Shortcut {
        Shortcut(keyCode: code, modifiers: modifiers, keyLabel: key(code).label)
    }

    /// ⌃⌥ as the window server writes it, to look for macOS shortcuts on the same keys.
    static let systemFlags: CGEventFlags = [.maskControl, .maskAlternate]
}
