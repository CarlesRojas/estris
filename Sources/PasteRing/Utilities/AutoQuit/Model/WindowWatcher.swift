import AppKit
import ApplicationServices

/// Watches regular apps and quits one once its last window has been closed.
///
/// An app only counts as having closed its last window if it was seen with a window first,
/// so apps opened without one (or that live in the menu bar) are left alone. Before
/// quitting, it also checks for windows the Accessibility API can't see, such as windows
/// on another desktop, and holds off if there might be any.
@MainActor
final class WindowWatcher: NSObject {
    private static let pollInterval: TimeInterval = 0.5
    /// Smaller windows (tool tips, helper panels) don't count as an app's window.
    private static let minimumWindowSide: CGFloat = 80

    private let settings: AutoQuitSettings
    private var timer: Timer?
    /// Apps seen with at least one window since watching started.
    private var hadWindows: Set<pid_t> = []
    /// When each app was first seen without windows after having had some.
    private var emptySince: [pid_t: Date] = [:]

    init(settings: AutoQuitSettings) {
        self.settings = settings
        super.init()
    }

    func start() {
        guard timer == nil else { return }
        hadWindows = []
        emptySince = [:]
        let timer = Timer(timeInterval: Self.pollInterval, target: self, selector: #selector(check), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    @objc private func check() {
        // Window lists come from the Accessibility API.
        guard Paster.isTrusted(prompt: false) else { return }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated && $0.processIdentifier != ownPID
        }
        let livePIDs = Set(apps.map(\.processIdentifier))
        hadWindows.formIntersection(livePIDs)
        emptySince = emptySince.filter { livePIDs.contains($0.key) }

        var otherWindows: [pid_t: Int]?
        for app in apps where !settings.keepsRunning(app.bundleIdentifier) {
            let pid = app.processIdentifier
            // Unknown (the app isn't answering) counts as having windows: never quit on doubt.
            let windowCount = Self.standardWindowCount(pid: pid) ?? 1
            if windowCount > 0 {
                hadWindows.insert(pid)
                emptySince[pid] = nil
                continue
            }
            guard hadWindows.contains(pid) else { continue }

            // Only look these up when an app actually ran out of windows.
            if otherWindows == nil {
                otherWindows = Self.possibleWindowCounts()
            }
            if otherWindows?[pid, default: 0] ?? 0 > 0 {
                emptySince[pid] = nil
                continue
            }

            let since = emptySince[pid] ?? Date()
            emptySince[pid] = since
            if Date().timeIntervalSince(since) >= settings.delay.interval {
                hadWindows.remove(pid)
                emptySince[pid] = nil
                app.terminate()
            }
        }
    }

    /// Document and app windows (not panels, sheets or palettes), including minimized ones,
    /// on the current desktop. Nil when the app can't be asked.
    private static func standardWindowCount(pid: pid_t) -> Int? {
        let application = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, "AXWindows" as CFString, &value) == .success,
              let windows = value as? [AXUIElement]
        else { return nil }
        return windows.filter { window in
            var subrole: CFTypeRef?
            AXUIElementCopyAttributeValue(window, "AXSubrole" as CFString, &subrole)
            return subrole as? String == "AXStandardWindow"
        }.count
    }

    /// Normal-level windows the window server knows about but that aren't on screen, per
    /// app: mostly windows on other desktops. Counted generously, so an app is never quit
    /// while it might still have a window somewhere.
    private static func possibleWindowCounts() -> [pid_t: Int] {
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return [:]
        }
        var counts: [pid_t: Int] = [:]
        for window in list {
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  (window[kCGWindowIsOnscreen as String] as? Bool) != true,
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let pid = window[kCGWindowOwnerPID as String] as? pid_t,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  (bounds["Width"] ?? 0) >= minimumWindowSide,
                  (bounds["Height"] ?? 0) >= minimumWindowSide
            else { continue }
            counts[pid, default: 0] += 1
        }
        return counts
    }
}
