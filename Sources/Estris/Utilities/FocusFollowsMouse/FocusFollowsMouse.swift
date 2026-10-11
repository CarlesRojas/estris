import AppKit
import ApplicationServices
import Combine
import SwiftUI

/// The Focus Follows Mouse utility: when the pointer rests on another app's window for the
/// chosen delay, with no mouse button or modifier key held, that window comes to the front
/// and its app becomes active. Menus, the Dock, the desktop, Estris's panels and excluded
/// apps are left alone. Owns everything it needs, so the app only has to create it
/// and call `start()`.
@MainActor
final class FocusFollowsMouse {
    /// Accessibility calls into a busy app give up after this long instead of stalling.
    private static let messagingTimeout: Float = 0.25

    let settings = FocusFollowsMouseSettings()
    private let appLog: AppLog
    private var observers: Set<AnyCancellable> = []
    private var tap: CFMachPort?
    private var spaceObserver: NSObjectProtocol?
    private var pending: DispatchWorkItem?
    private var lastPoint: NSPoint?
    private var lastTime: TimeInterval = 0
    /// The pointer's speed, smoothed over the last few moves.
    private var speed: CGFloat = 0
    /// The window under the pointer, and since when it has been there moving slowly.
    private var candidate = 0
    private var dwellStart: TimeInterval = 0
    /// Whether the candidate was already handled, so slow moves over it don't repeat the work.
    private var isHandled = false

    init(log: AppLog) {
        appLog = log
    }

    func start() {
        settings.$isEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in self?.setActive(enabled) }
            .store(in: &observers)
    }

    /// The pane shown for this utility in Settings.
    func settingsPane() -> some View {
        FocusFollowsMousePane(settings: settings)
    }

    private func setActive(_ active: Bool) {
        pending?.cancel()
        pending = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
        spaceObserver = nil
        guard active else { return }

        // A listen-only event tap: unlike a global event monitor, it also sees moves over
        // Estris's own windows (Settings).
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        } else {
            tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .tailAppendEventTap,
                options: .listenOnly,
                eventsOfInterest: CGEventMask(1 << CGEventType.mouseMoved.rawValue),
                callback: focusFollowsMouseCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
            guard let tap else { return log("can't watch the pointer; needs Accessibility access") }
            CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        }
        // Switching desktops moves windows under a still pointer; that isn't the user picking one.
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pending?.cancel()
                self?.pending = nil
                self?.candidate = 0
            }
        }
    }

    /// Counts how long the pointer stays over the same window while moving slowly (or resting);
    /// moving fast or entering another window starts the count again, so windows crossed on
    /// the way aren't brought forward. Once it reaches the delay, the window is focused.
    fileprivate func handle(_ type: CGEventType) {
        switch type {
        case .mouseMoved:
            pointerMoved(at: ProcessInfo.processInfo.systemUptime)
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap, settings.isEnabled { CGEvent.tapEnable(tap: tap, enable: true) }
        default:
            break
        }
    }

    private func pointerMoved(at time: TimeInterval) {
        let point = NSEvent.mouseLocation
        if let lastPoint, time > lastTime {
            let moved = hypot(point.x - lastPoint.x, point.y - lastPoint.y) / CGFloat(time - lastTime)
            speed = speed * 0.6 + moved * 0.4
        }
        lastPoint = point
        lastTime = time

        let number = NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0)
        if number != candidate {
            candidate = number
            dwellStart = time
            isHandled = false
        }
        if speed > CGFloat(settings.passThroughSpeed) {
            dwellStart = time
        }
        guard !isHandled else { return }

        let waited = time - dwellStart
        pending?.cancel()
        pending = nil
        if waited >= settings.delay.seconds {
            focusWindowUnderPointer()
            return
        }
        // If the pointer stops before then, no more moves arrive: finish the count anyway.
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.candidate == number, !self.isHandled else { return }
                self.speed = 0
                self.focusWindowUnderPointer()
            }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + settings.delay.seconds - waited, execute: work)
    }

    private func focusWindowUnderPointer() {
        pending = nil
        guard settings.isEnabled, AXIsProcessTrusted(),
              // Dragging, clicking, or holding a modifier for a shortcut; tried again on the
              // next move.
              NSEvent.pressedMouseButtons == 0,
              NSEvent.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
        else { return }

        let point = NSEvent.mouseLocation
        let number = NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0)
        // An app that just opened, often away from the pointer, keeps the focus for a while;
        // tried again on the next move.
        if settings.keepsNewAppsInFront, let front = NSWorkspace.shared.frontmostApplication,
           let launched = front.launchDate, Date().timeIntervalSince(launched) < settings.newAppSeconds,
           Self.windowInfo(CGWindowID(max(number, 0)))?.pid != front.processIdentifier {
            return
        }
        isHandled = true

        // The window a click would reach, on top of everything; nothing to do over menus, the
        // Dock, the menu bar or the desktop, which aren't normal windows (layer 0).
        guard number > 0, let info = Self.windowInfo(CGWindowID(number)), info.layer == 0 else { return }
        // Estris's own: only its titled windows (Settings), not its panels.
        if info.pid == ProcessInfo.processInfo.processIdentifier {
            if let window = NSApp.window(withWindowNumber: number), window.styleMask.contains(.titled),
               !(NSApp.isActive && window.isKeyWindow) {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                log("focused \(window.title)")
            }
            return
        }
        guard let app = NSRunningApplication(processIdentifier: info.pid),
              app.activationPolicy == .regular, !app.isTerminated
        else { return }
        if let bundleID = app.bundleIdentifier, settings.excludedApps.contains(bundleID) { return }

        let appElement = AXUIElementCreateApplication(info.pid)
        AXUIElementSetMessagingTimeout(appElement, Self.messagingTimeout)
        guard let window = Self.window(at: AXWindow.axPoint(point), in: appElement) else { return }

        let focused = Self.element(appElement, kAXFocusedWindowAttribute)
        let isFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == info.pid
        if isFrontmost, let focused {
            // Already the focused window.
            if CFEqual(focused, window) { return }
            // A sheet or a modal dialog keeps focus until it is answered.
            if Self.string(focused, kAXRoleAttribute) == kAXSheetRole as String || Self.isModal(focused) { return }
        }

        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        if !isFrontmost {
            if #available(macOS 14, *) {
                app.activate()
            } else {
                app.activate(options: [])
            }
        }
        log("focused \(app.localizedName ?? "\(info.pid)")\(Self.string(window, kAXTitleAttribute).map { ": \($0)" } ?? "")")
    }

    // MARK: Windows

    private struct WindowInfo {
        let pid: pid_t
        let layer: Int
    }

    private static func windowInfo(_ id: CGWindowID) -> WindowInfo? {
        guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]],
              let entry = list.first,
              let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
              let layer = entry[kCGWindowLayer as String] as? Int
        else { return nil }
        return WindowInfo(pid: pid, layer: layer)
    }

    /// The app's own top-level window at a point, asked of the app only.
    private static func window(at point: CGPoint, in app: AXUIElement) -> AXUIElement? {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(app, Float(point.x), Float(point.y), &hit) == .success, let hit else { return nil }
        AXUIElementSetMessagingTimeout(hit, messagingTimeout)
        let window = string(hit, kAXRoleAttribute) == kAXWindowRole as String ? hit : element(hit, kAXWindowAttribute)
        guard let window, string(window, kAXRoleAttribute) == kAXWindowRole as String else { return nil }
        return window
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func isModal(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, kAXModalAttribute as CFString, &value) == .success
            && (value as? Bool) == true
    }

    private func log(_ message: String) {
        appLog.record(message, source: "Focus Follows Mouse")
    }
}

/// Plain C function for the event tap; the utility comes back through the refcon. Runs on the
/// main run loop, where the tap is scheduled.
private func focusFollowsMouseCallback(
    _ proxy: CGEventTapProxy,
    _ type: CGEventType,
    _ event: CGEvent,
    _ refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if let refcon {
        let utility = Unmanaged<FocusFollowsMouse>.fromOpaque(refcon).takeUnretainedValue()
        MainActor.assumeIsolated { utility.handle(type) }
    }
    return Unmanaged.passUnretained(event)
}
