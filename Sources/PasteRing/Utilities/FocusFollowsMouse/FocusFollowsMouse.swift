import AppKit
import ApplicationServices
import Combine
import SwiftUI

/// The Focus Follows Mouse utility: when the pointer rests on another app's window for the
/// chosen delay, with no mouse button or modifier key held, that window comes to the front
/// and its app becomes active. Menus, the Dock, the desktop, PasteRing's own windows and
/// excluded apps are left alone. Owns everything it needs, so the app only has to create it
/// and call `start()`.
@MainActor
final class FocusFollowsMouse {
    /// Accessibility calls into a busy app give up after this long instead of stalling.
    private static let messagingTimeout: Float = 0.25
    /// Faster than this (points per second) is passing through on the way somewhere else.
    private static let fastSpeed: CGFloat = 800

    let settings = FocusFollowsMouseSettings()
    private let appLog: AppLog
    private var observers: Set<AnyCancellable> = []
    private var mouseMonitor: Any?
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
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
        spaceObserver = nil
        guard active else { return }

        // Moves over other apps' windows; PasteRing's own windows are never focused this way.
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            let time = event.timestamp
            MainActor.assumeIsolated { self?.pointerMoved(at: time) }
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
        if speed > Self.fastSpeed {
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
        isHandled = true

        let point = NSEvent.mouseLocation
        // The window a click would reach, on top of everything; nothing to do over menus, the
        // Dock, the menu bar or the desktop, which aren't normal windows (layer 0).
        let number = NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0)
        guard number > 0, let info = Self.windowInfo(CGWindowID(number)),
              info.layer == 0, info.pid != ProcessInfo.processInfo.processIdentifier,
              let app = NSRunningApplication(processIdentifier: info.pid),
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
