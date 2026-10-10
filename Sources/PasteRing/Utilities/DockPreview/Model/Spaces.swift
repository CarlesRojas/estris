import AppKit

/// Which desktop (Space) a window is on, and going there. macOS has no public API for either;
/// the window server's own calls are looked up at run time, and everything falls back to plain
/// app activation when they're missing.
enum Spaces {
    private typealias Connection = UInt32

    private static func symbol(_ name: String) -> UnsafeMutableRawPointer? {
        dlsym(UnsafeMutableRawPointer(bitPattern: -2), name)
    }

    private static let connection: Connection = {
        guard let symbol = symbol("CGSMainConnectionID") else { return 0 }
        return unsafeBitCast(symbol, to: (@convention(c) () -> Connection).self)()
    }()

    private static let copySpacesForWindows: (@convention(c) (Connection, Int32, CFArray) -> Unmanaged<CFArray>?)? = {
        guard let symbol = symbol("CGSCopySpacesForWindows") else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (Connection, Int32, CFArray) -> Unmanaged<CFArray>?).self)
    }()

    private static let copyManagedDisplaySpaces: (@convention(c) (Connection) -> Unmanaged<CFArray>?)? = {
        guard let symbol = symbol("CGSCopyManagedDisplaySpaces") else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (Connection) -> Unmanaged<CFArray>?).self)
    }()

    /// The desktops a window is on.
    static func spaces(of window: CGWindowID) -> [UInt64] {
        guard connection != 0, let copySpacesForWindows,
              let list = copySpacesForWindows(connection, 0x7, [NSNumber(value: window)] as CFArray)?.takeRetainedValue() as? [NSNumber]
        else { return [] }
        return list.map(\.uint64Value)
    }

    /// Each display's desktops, left to right, and the one it shows.
    static func displays() -> [(spaces: [UInt64], current: UInt64?)] {
        guard connection != 0, let copyManagedDisplaySpaces,
              let list = copyManagedDisplaySpaces(connection)?.takeRetainedValue() as? [[String: Any]]
        else { return [] }
        return list.map { display in
            let spaces = (display["Spaces"] as? [[String: Any]] ?? []).compactMap { ($0["id64"] as? NSNumber)?.uint64Value }
            let current = ((display["Current Space"] as? [String: Any])?["id64"] as? NSNumber)?.uint64Value
            return (spaces, current)
        }
    }

    static var visible: Set<UInt64> {
        Set(displays().compactMap(\.current))
    }

    /// On a desktop, but none that is showing.
    static func isOnHiddenSpace(_ window: CGWindowID) -> Bool {
        let spaces = spaces(of: window)
        let visible = visible
        return !spaces.isEmpty && !visible.isEmpty && spaces.allSatisfy { !visible.contains($0) }
    }

    /// How many desktops to the right (positive) or left the window's is from the one showing
    /// on its display; nil when it can't be told.
    static func steps(to window: CGWindowID) -> Int? {
        guard let target = spaces(of: window).first else { return nil }
        for display in displays() {
            guard let targetIndex = display.spaces.firstIndex(of: target),
                  let current = display.current,
                  let currentIndex = display.spaces.firstIndex(of: current)
            else { continue }
            return targetIndex - currentIndex
        }
        return nil
    }

    // MARK: The user's "Move left/right a space" shortcuts

    private static let hotKeyValue: (@convention(c) (Int32, UnsafeMutablePointer<UInt32>, UnsafeMutablePointer<UInt32>, UnsafeMutablePointer<UInt32>) -> CGError)? = {
        guard let symbol = symbol("CGSGetSymbolicHotKeyValue") else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (Int32, UnsafeMutablePointer<UInt32>, UnsafeMutablePointer<UInt32>, UnsafeMutablePointer<UInt32>) -> CGError).self)
    }()

    private static let hotKeyEnabled: (@convention(c) (Int32) -> Bool)? = {
        guard let symbol = symbol("CGSIsSymbolicHotKeyEnabled") else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (Int32) -> Bool).self)
    }()

    /// Presses the shortcut set in System Settings > Keyboard > Shortcuts > Mission Control,
    /// as the user would. False when it's turned off or can't be read.
    @discardableResult
    static func pressMove(right: Bool) -> Bool {
        let id: Int32 = right ? 81 : 79
        guard let hotKeyValue, let hotKeyEnabled, hotKeyEnabled(id) else { return false }
        var options: UInt32 = 0
        var keyCode: UInt32 = 0
        var modifiers: UInt32 = 0
        guard hotKeyValue(id, &options, &keyCode, &modifiers) == .success, keyCode != 0,
              let down = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: false)
        else { return false }
        var flags = CGEventFlags()
        if modifiers & 0x20000 != 0 { flags.insert(.maskShift) }
        if modifiers & 0x40000 != 0 { flags.insert(.maskControl) }
        if modifiers & 0x80000 != 0 { flags.insert(.maskAlternate) }
        if modifiers & 0x100000 != 0 { flags.insert(.maskCommand) }
        if modifiers & 0x800000 != 0 { flags.insert(.maskSecondaryFn) }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}

/// Goes to the desktop a window is on, then brings the window forward: activating the app
/// first (macOS travels there by itself when the app has no window on the desktop showing),
/// then pressing the user's "Move left/right a space" shortcut one desktop at a time, checking
/// after each that the desktop changed.
@available(macOS 14, *)
@MainActor
final class SpaceTrip {
    private static var current: SpaceTrip?
    /// A desktop switch is reported once its animation ends.
    private static let arrivalTimeout: TimeInterval = 1.2

    private let window: CGWindowID
    private let app: NSRunningApplication
    private let arrived: () -> Void
    private var pressesLeft = 16
    private var isCancelled = false

    static func go(to window: CGWindowID, of app: NSRunningApplication, then arrived: @escaping () -> Void) {
        current?.isCancelled = true
        let trip = SpaceTrip(window: window, app: app, arrived: arrived)
        current = trip
        trip.start()
    }

    private init(window: CGWindowID, app: NSRunningApplication, arrived: @escaping () -> Void) {
        self.window = window
        self.app = app
        self.arrived = arrived
    }

    private func start() {
        app.unhide()
        let hasWindowHere = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? [])
            .contains { $0[kCGWindowOwnerPID as String] as? pid_t == app.processIdentifier && $0[kCGWindowLayer as String] as? Int == 0 }
        if hasWindowHere {
            app.activate()
            step()
        } else {
            // macOS goes to a desktop where the app has windows.
            app.activate(options: [.activateAllWindows])
            wait(from: Spaces.visible) { [weak self] moved in
                guard let self else { return }
                if !Spaces.isOnHiddenSpace(self.window) { self.finish() } else { self.step() }
                _ = moved
            }
        }
    }

    /// One press toward the window's desktop.
    private func step() {
        guard !isCancelled else { return }
        guard Spaces.isOnHiddenSpace(window) else { return finish() }
        guard pressesLeft > 0, let steps = Spaces.steps(to: window), steps != 0,
              Spaces.pressMove(right: steps > 0)
        else { return finish() }
        pressesLeft -= 1
        wait(from: Spaces.visible) { [weak self] moved in
            // A press that changed nothing: the shortcut went elsewhere; stop.
            if moved { self?.step() } else { self?.finish() }
        }
    }

    /// Calls back once the desktop showing changes, or after the time a switch takes.
    private func wait(from before: Set<UInt64>, deadline: Date = Date().addingTimeInterval(SpaceTrip.arrivalTimeout), then done: @escaping (Bool) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isCancelled else { return }
                if Spaces.visible != before { return done(true) }
                if Date() > deadline { return done(false) }
                self.wait(from: before, deadline: deadline, then: done)
            }
        }
    }

    /// Accessibility describes the window shortly after its desktop shows; a few tries cover it.
    private func finish() {
        guard !isCancelled else { return }
        for delay in [0.15, 0.45, 0.9] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, !self.isCancelled else { return }
                    self.arrived()
                }
            }
        }
        if Self.current === self { Self.current = nil }
    }
}

/// Keeps an automatically hidden Dock showing while the preview is open, by turning autohide
/// off for that time (CoreDock, looked up at run time). A marker saved first puts it back at
/// the next launch should PasteRing quit before it could.
enum DockHold {
    private static let restoreKey = "dockPreviewRestoreAutohide"

    private static let handle = dlopen("/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices", RTLD_LAZY)
    private static let getAutohide: (@convention(c) () -> UInt8)? = handle.flatMap { dlsym($0, "CoreDockGetAutoHideEnabled") }
        .map { unsafeBitCast($0, to: (@convention(c) () -> UInt8).self) }
    private static let setAutohide: (@convention(c) (UInt8) -> Void)? = handle.flatMap { dlsym($0, "CoreDockSetAutoHideEnabled") }
        .map { unsafeBitCast($0, to: (@convention(c) (UInt8) -> Void).self) }

    static var isHolding: Bool { UserDefaults.standard.bool(forKey: restoreKey) }

    /// Only when the Dock hides itself.
    static func begin() {
        guard !isHolding, let getAutohide, let setAutohide, getAutohide() != 0 else { return }
        UserDefaults.standard.set(true, forKey: restoreKey)
        setAutohide(0)
    }

    static func end() {
        guard isHolding, let setAutohide else { return }
        setAutohide(1)
        UserDefaults.standard.removeObject(forKey: restoreKey)
    }
}
