import AppKit

/// The windows on screen, front to back, as Seasons sees them: where their top edges are, and
/// how they are stacked. Read from the window list, which gives frames without any
/// permission.
struct WindowSnapshot {
    struct Window {
        let id: CGWindowID
        /// In AppKit's global coordinates (origin at the bottom left of the main screen).
        let frame: CGRect
        /// How round its top corners are.
        var cornerRadius: CGFloat = WindowSnapshot.windowCornerRadius
    }

    /// The corners of macOS's windows: rounder since macOS 26.
    static let windowCornerRadius: CGFloat = ProcessInfo.processInfo.isOperatingSystemAtLeast(
        OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)
    ) ? 16 : 10

    /// Normal windows (not the menu bar, the Dock or panels above them), front first.
    let windows: [Window]
    /// Every normal window, Seasons' own pile windows too, front first.
    let order: [CGWindowID]

    /// The windows, leaving out `own`: Seasons' pile windows, which piles don't land on.
    static func read(excluding own: Set<CGWindowID> = []) -> WindowSnapshot {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return WindowSnapshot(windows: [], order: [])
        }
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        let order = list.compactMap { info -> CGWindowID? in
            guard (info[kCGWindowLayer as String] as? Int) == 0 else { return nil }
            return info[kCGWindowNumber as String] as? CGWindowID
        }
        let windows = list.compactMap { info -> Window? in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.05,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  !own.contains(id),
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary),
                  bounds.width >= 80, bounds.height >= 40
            else { return nil }
            // The window list measures from the top left of the main screen.
            let frame = CGRect(x: bounds.minX, y: mainHeight - bounds.maxY, width: bounds.width, height: bounds.height)
            return Window(id: id, frame: frame)
        }
        return WindowSnapshot(windows: windows, order: order)
    }

    /// Whether one window is right in front of another, with nothing between them.
    func isJustInFront(_ window: CGWindowID, of other: CGWindowID) -> Bool {
        guard let index = order.firstIndex(of: window), index + 1 < order.count else { return false }
        return order[index + 1] == other
    }

    /// Whether a window fills this screen, as a full screen app does.
    func hasFullScreenWindow(on screen: CGRect) -> Bool {
        windows.contains { abs($0.frame.minX - screen.minX) < 1 && abs($0.frame.minY - screen.minY) < 1
            && abs($0.frame.width - screen.width) < 1 && abs($0.frame.height - screen.height) < 1 }
    }
}
