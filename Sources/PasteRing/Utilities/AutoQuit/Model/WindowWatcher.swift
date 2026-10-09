import AppKit
import ApplicationServices

/// Quits an app once its last window has closed, reacting to window events instead of
/// polling.
///
/// Every regular app gets an Accessibility observer. It hears when the app creates or
/// focuses windows (each window is then watched for being destroyed), and when a watched
/// window is destroyed the app's windows are looked at a few times over the next couple of
/// seconds. If the app has none left, it is checked once more after the chosen delay and
/// then asked to quit (a normal quit, so unsaved changes can still be saved).
///
/// Left alone: apps never seen with a window, menu bar and background apps, hidden apps,
/// excluded apps, and apps that may still have a window the Accessibility API can't see,
/// such as one on another desktop.
@MainActor
final class WindowWatcher {
    /// Looks after a window is destroyed. A closing window stays on screen while it fades
    /// out, so one early look can still see it; later looks catch it gone.
    private static let checkOffsets: [TimeInterval] = [0.35, 1.0, 2.2]
    /// Leaving full screen destroys the full-screen window a moment before the normal one
    /// comes back, so an empty app is always confirmed once more before quitting.
    private static let minimumConfirmDelay: TimeInterval = 1.2
    /// Longest any single Accessibility request may block, so a busy app can't freeze us.
    private static let messagingTimeout: Float = 0.35
    /// Smaller windows (tool tips, helper panels) don't count as an app's window.
    private static let minimumWindowSide: CGFloat = 80

    private let settings: AutoQuitSettings
    private var isRunning = false
    private var observers: [pid_t: AXObserver] = [:]
    /// Apps seen with at least one window since watching started.
    private var hadWindows: Set<pid_t> = []
    /// Last time a round of checks was scheduled per app, so closing several windows at
    /// once schedules one round.
    private var lastCheckRound: [pid_t: Date] = [:]
    private var workspaceTokens: [NSObjectProtocol] = []

    init(settings: AutoQuitSettings) {
        self.settings = settings
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        let center = NSWorkspace.shared.notificationCenter
        let app = { (note: Notification) in note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication }
        workspaceTokens = [
            center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated { app(note).map { self?.attach($0) } }
            },
            center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated { app(note).map { self?.detach(pid: $0.processIdentifier) } }
            },
            // Some apps only become regular (take a Dock icon) once they show a window, so
            // they're missed at launch; coming to the front is a sure moment to catch them.
            center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated { app(note).map { self?.attach($0) } }
            },
        ]
        NSWorkspace.shared.runningApplications.forEach(attach)
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        let center = NSWorkspace.shared.notificationCenter
        workspaceTokens.forEach(center.removeObserver)
        workspaceTokens = []
        Array(observers.keys).forEach(detach)
        hadWindows = []
        lastCheckRound = [:]
    }

    // MARK: - Observers

    private func attach(_ app: NSRunningApplication) {
        guard isRunning, app.activationPolicy == .regular else { return }
        let pid = app.processIdentifier
        guard pid != getpid() else { return }
        if let observer = observers[pid] {
            watchWindows(pid: pid, observer: observer)
            return
        }

        var created: AXObserver?
        let result = AXObserverCreate(pid, windowWatcherCallback, &created)
        guard result == .success, let observer = created else {
            // Usually missing Accessibility permission; tried again when the app comes forward.
            return log("\(app.localizedName ?? "pid \(pid)"): can't watch (error \(result.rawValue))")
        }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, Self.messagingTimeout)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for notification in [kAXWindowCreatedNotification, kAXMainWindowChangedNotification, kAXFocusedWindowChangedNotification] {
            AXObserverAddNotification(observer, application, notification as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        observers[pid] = observer
        watchWindows(pid: pid, observer: observer)
    }

    private func detach(pid: pid_t) {
        if let observer = observers.removeValue(forKey: pid) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        hadWindows.remove(pid)
        lastCheckRound[pid] = nil
    }

    /// Registers for each current window's destruction, and notes the app has had windows.
    private func watchWindows(pid: pid_t, observer: AXObserver) {
        let windows = Self.standardWindows(pid: pid) ?? []
        guard !windows.isEmpty else { return }
        hadWindows.insert(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for window in windows {
            // Registering a window twice is harmless; it just reports it's already watched.
            AXObserverAddNotification(observer, window, kAXUIElementDestroyedNotification as CFString, refcon)
        }
    }

    /// Called from the observer callback, on the main run loop.
    fileprivate func handle(notification: String, observer: AXObserver, element: AXUIElement) {
        guard let pid = observers.first(where: { CFEqual($0.value, observer) })?.key else { return }
        if notification == kAXUIElementDestroyedNotification as String {
            log("\(NSRunningApplication(processIdentifier: pid)?.localizedName ?? "pid \(pid)"): a window closed")
            scheduleChecks(pid: pid)
        } else {
            watchWindows(pid: pid, observer: observer)
        }
    }

    // MARK: - Deciding to quit

    private func scheduleChecks(pid: pid_t) {
        let now = Date()
        if let last = lastCheckRound[pid], now.timeIntervalSince(last) < 0.25 { return }
        lastCheckRound[pid] = now
        for offset in Self.checkOffsets {
            DispatchQueue.main.asyncAfter(deadline: .now() + offset) { [weak self] in
                self?.check(pid: pid, confirming: false)
            }
        }
    }

    private func check(pid: pid_t, confirming: Bool) {
        guard isRunning, let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return }
        let name = app.localizedName ?? "pid \(pid)"
        // Logged so a quit that doesn't happen can be traced in Console (search "Auto Quit").
        guard hadWindows.contains(pid) else { return log("\(name): never seen with a window") }
        guard !app.isHidden else { return log("\(name): hidden, left running") }
        guard !settings.keepsRunning(app.bundleIdentifier) else { return log("\(name): excluded") }
        guard !Self.isBackgroundApp(app) else { return log("\(name): menu bar or background app") }
        if let windows = Self.standardWindows(pid: pid) {
            guard windows.isEmpty else { return log("\(name): still has \(windows.count) window(s)") }
        } else {
            return log("\(name): didn't answer, left running")
        }
        guard !Self.hasWindowServerWindow(pid: pid) else { return log("\(name): window server still shows a window") }

        guard confirming else {
            let delay = max(Self.minimumConfirmDelay, settings.delay.interval)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.check(pid: pid, confirming: true)
            }
            return
        }
        hadWindows.remove(pid)
        log("\(name): no windows left, quitting")
        app.terminate()
    }

    private func log(_ message: String) {
        NSLog("PasteRing Auto Quit: %@", message)
    }

    /// Document and app windows (not panels, sheets or palettes) on the current desktop,
    /// minimized ones included. Nil when the app doesn't answer.
    private static func standardWindows(pid: pid_t) -> [AXUIElement]? {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, messagingTimeout)
        // Asks for windows rather than anything else about the app: Chromium-based apps
        // switch on full accessibility (and keep paying for it) when asked other things.
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement]
        else { return nil }
        return windows.filter { window in
            AXUIElementSetMessagingTimeout(window, messagingTimeout)
            var subrole: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subrole)
            let value = subrole as? String
            return value == "AXStandardWindow" || value == "AXFullScreenWindow"
        }
    }

    /// Whether the window server shows a window of the app that the Accessibility API
    /// missed. Only on-screen windows count: almost every app keeps hidden, off-screen
    /// windows after its last one closes, so counting those meant nothing was ever quit.
    /// An off-screen window counts only when it has a title, which macOS reports for other
    /// apps' windows only with the Screen Recording permission; without it, a window on
    /// another desktop can't be told apart from a hidden one.
    private static func hasWindowServerWindow(pid: pid_t) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        return list.contains { window in
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  ((window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let width = (bounds["Width"] as? NSNumber)?.doubleValue,
                  let height = (bounds["Height"] as? NSNumber)?.doubleValue,
                  width >= minimumWindowSide, height >= minimumWindowSide
            else { return false }
            if (window[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue == true {
                return true
            }
            let title = window[kCGWindowName as String] as? String ?? ""
            return !title.isEmpty
        }
    }

    /// Menu bar and background-only apps take a Dock icon only while a window such as
    /// their settings is open; closing it isn't a reason to quit them.
    private static func isBackgroundApp(_ app: NSRunningApplication) -> Bool {
        guard let url = app.bundleURL, let info = Bundle(url: url)?.infoDictionary else { return false }
        return info["LSUIElement"] as? Bool == true || info["LSBackgroundOnly"] as? Bool == true
    }
}

/// Plain C function for AXObserver; the watcher comes back through the refcon.
private func windowWatcherCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let watcher = Unmanaged<WindowWatcher>.fromOpaque(refcon).takeUnretainedValue()
    MainActor.assumeIsolated {
        watcher.handle(notification: notification as String, observer: observer, element: element)
    }
}
