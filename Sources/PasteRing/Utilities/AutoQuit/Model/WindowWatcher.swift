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
    /// Waits before asking again an app that refused or didn't answer while being set up
    /// (busy launching, or not yet accepting Accessibility requests).
    private static let attachRetryDelays: [TimeInterval] = [0.15, 0.4, 1.0, 2.5, 5.0, 10.0]
    /// Looks again, from the first miss, when a window isn't watched yet: the Accessibility
    /// API often lists a new window late, and a window nobody watches closes silently.
    private static let windowRetryOffsets: [TimeInterval] = [0.5, 1.5, 4.0]

    private let settings: AutoQuitSettings
    private var isRunning = false
    private var observers: [pid_t: AXObserver] = [:]
    /// Apps seen with at least one window since watching started.
    private var hadWindows: Set<pid_t> = []
    /// Last time a round of checks was scheduled per app, so closing several windows at
    /// once schedules one round.
    private var lastCheckRound: [pid_t: Date] = [:]
    /// Apps in a round of attach retries, so coming to the front doesn't start another.
    private var attachRetries: Set<pid_t> = []
    /// Apps in a round of window retries: when the round started and how many looks are queued.
    private var windowRetries: [pid_t: (origin: DispatchTime, scheduled: Int)] = [:]
    private var workspaceTokens: [NSObjectProtocol] = []

    private let appLog: AppLog

    init(settings: AutoQuitSettings, log: AppLog) {
        self.settings = settings
        appLog = log
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
            // Windows on a desktop that wasn't visible can only be seen once it is.
            center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshAll() }
            },
        ]
        NSWorkspace.shared.runningApplications.forEach(attach)
        log("started, watching \(observers.count) apps, Accessibility \(AXIsProcessTrusted() ? "granted" : "NOT granted")")
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        log("stopped")
        let center = NSWorkspace.shared.notificationCenter
        workspaceTokens.forEach(center.removeObserver)
        workspaceTokens = []
        Array(observers.keys).forEach(detach)
        hadWindows = []
        lastCheckRound = [:]
        attachRetries = []
        windowRetries = [:]
    }

    // MARK: - Observers

    private func attach(_ app: NSRunningApplication) {
        attach(app, attempt: 0)
    }

    private func attach(_ app: NSRunningApplication, attempt: Int) {
        guard isRunning, app.activationPolicy == .regular, !app.isTerminated else { return }
        let pid = app.processIdentifier
        guard pid != getpid() else { return }
        if let observer = observers[pid] {
            windowRetries[pid] = nil
            watchWindows(pid: pid, observer: observer)
            return
        }
        if attempt == 0, attachRetries.contains(pid) { return }
        let name = app.localizedName ?? "pid \(pid)"

        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, Self.messagingTimeout)
        var attached: AXObserver?
        var failure: AXError?
        var created: AXObserver?
        let result = AXObserverCreate(pid, windowWatcherCallback, &created)
        if result == .success, let created {
            let refcon = Unmanaged.passUnretained(self).toOpaque()
            var listening = 0
            for notification in [kAXWindowCreatedNotification, kAXMainWindowChangedNotification, kAXFocusedWindowChangedNotification, kAXApplicationShownNotification] {
                let added = AXObserverAddNotification(created, application, notification as CFString, refcon)
                if added == .success || added == .notificationAlreadyRegistered {
                    listening += 1
                } else {
                    failure = added
                }
            }
            // Partly listening is still useful; not listening at all means the app isn't ready.
            if listening > 0 { attached = created }
        } else {
            failure = result
        }

        guard let observer = attached else {
            // A launching or busy app can refuse at first; ask again a few times, spaced out.
            guard attempt < Self.attachRetryDelays.count else {
                attachRetries.remove(pid)
                return log("\(name): can't watch (error \(failure?.rawValue ?? 0)), will try again when it comes to the front")
            }
            if attempt == 0 { log("\(name): not ready to be watched (error \(failure?.rawValue ?? 0)), retrying") }
            attachRetries.insert(pid)
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.attachRetryDelays[attempt]) { [weak self] in
                self?.attach(app, attempt: attempt + 1)
            }
            return
        }
        if attempt > 0 { log("\(name): watching after \(attempt) retries") }
        attachRetries.remove(pid)
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
        attachRetries.remove(pid)
        windowRetries[pid] = nil
    }

    private func refreshAll() {
        for (pid, observer) in observers {
            windowRetries[pid] = nil
            watchWindows(pid: pid, observer: observer)
        }
    }

    /// Registers for each current window's destruction, and notes the app has had windows.
    /// Looks again shortly when a window may be left unwatched.
    private func watchWindows(pid: pid_t, observer: AXObserver) {
        let windows = Self.standardWindows(pid: pid) ?? []
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        var watched = 0
        for window in windows {
            // Registering a window twice is harmless; it just reports it's already watched.
            let added = AXObserverAddNotification(observer, window, kAXUIElementDestroyedNotification as CFString, refcon)
            if added == .success || added == .notificationAlreadyRegistered { watched += 1 }
        }
        // The window server may show a window the Accessibility API doesn't list yet.
        let hasWindow = !windows.isEmpty || Self.hasWindowServerWindow(pid: pid)
        if hasWindow, hadWindows.insert(pid).inserted {
            log("\(NSRunningApplication(processIdentifier: pid)?.localizedName ?? "pid \(pid)"): watching \(watched) of \(max(windows.count, 1)) window(s)")
        }

        let needsRetry = hasWindow ? watched < max(windows.count, 1) : !hadWindows.contains(pid)
        guard needsRetry else {
            windowRetries[pid] = nil
            return
        }
        var retry = windowRetries[pid] ?? (origin: .now(), scheduled: 0)
        guard retry.scheduled < Self.windowRetryOffsets.count else { return }
        let offset = Self.windowRetryOffsets[retry.scheduled]
        retry.scheduled += 1
        windowRetries[pid] = retry
        let round = retry.origin
        DispatchQueue.main.asyncAfter(deadline: round + offset) { [weak self] in
            // Skipped when a newer round replaced this one, or the app went away.
            guard let self, self.isRunning, self.windowRetries[pid]?.origin == round,
                  let observer = self.observers[pid] else { return }
            self.watchWindows(pid: pid, observer: observer)
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
        appLog.record(message, source: "Auto Quit")
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
