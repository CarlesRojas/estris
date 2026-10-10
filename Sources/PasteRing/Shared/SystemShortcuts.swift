import CoreGraphics
import Foundation

/// macOS's own keyboard shortcuts (System Settings > Keyboard > Keyboard Shortcuts), read
/// through the window server's calls, looked up at run time.
enum SystemShortcuts {
    /// Mission Control: move one desktop left or right.
    static let moveLeftASpace: Int32 = 79
    static let moveRightASpace: Int32 = 81
    /// Input Sources: select the next source in the Input menu (⌃⌥Space unless changed).
    static let selectNextInputSource: Int32 = 61

    private static func symbol(_ name: String) -> UnsafeMutableRawPointer? {
        dlsym(UnsafeMutableRawPointer(bitPattern: -2), name)
    }

    private static let valueFunction: (@convention(c) (Int32, UnsafeMutablePointer<UInt32>, UnsafeMutablePointer<UInt32>, UnsafeMutablePointer<UInt32>) -> CGError)? = {
        guard let symbol = symbol("CGSGetSymbolicHotKeyValue") else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (Int32, UnsafeMutablePointer<UInt32>, UnsafeMutablePointer<UInt32>, UnsafeMutablePointer<UInt32>) -> CGError).self)
    }()

    private static let enabledFunction: (@convention(c) (Int32) -> Bool)? = {
        guard let symbol = symbol("CGSIsSymbolicHotKeyEnabled") else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (Int32) -> Bool).self)
    }()

    /// The key and modifiers of a shortcut that is turned on; nil when it's off or can't be read.
    static func shortcut(_ id: Int32) -> (keyCode: CGKeyCode, flags: CGEventFlags)? {
        guard let valueFunction, let enabledFunction, enabledFunction(id) else { return nil }
        var options: UInt32 = 0
        var keyCode: UInt32 = 0
        var modifiers: UInt32 = 0
        guard valueFunction(id, &options, &keyCode, &modifiers) == .success, keyCode != 0, keyCode != 0xFFFF else { return nil }
        var flags = CGEventFlags()
        if modifiers & 0x20000 != 0 { flags.insert(.maskShift) }
        if modifiers & 0x40000 != 0 { flags.insert(.maskControl) }
        if modifiers & 0x80000 != 0 { flags.insert(.maskAlternate) }
        if modifiers & 0x100000 != 0 { flags.insert(.maskCommand) }
        if modifiers & 0x800000 != 0 { flags.insert(.maskSecondaryFn) }
        return (CGKeyCode(keyCode), flags)
    }

    /// Whether a turned-on macOS shortcut is this key with exactly these modifiers (fn aside).
    static func isTaken(keyCode: CGKeyCode, flags: CGEventFlags, by id: Int32) -> Bool {
        guard let shortcut = shortcut(id) else { return false }
        let modifiers: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand]
        return shortcut.keyCode == keyCode && shortcut.flags.intersection(modifiers) == flags.intersection(modifiers)
    }
}
