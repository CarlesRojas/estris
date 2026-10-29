import AppKit

/// The windows on screen, front to back, as Seasons sees them: where their top edges are and
/// what lies in front of them. Read from the window list, which gives frames without any
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

    static func read() -> WindowSnapshot {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return WindowSnapshot(windows: [])
        }
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        let windows = list.compactMap { info -> Window? in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.05,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary),
                  bounds.width >= 80, bounds.height >= 40
            else { return nil }
            // The window list measures from the top left of the main screen.
            let frame = CGRect(x: bounds.minX, y: mainHeight - bounds.maxY, width: bounds.width, height: bounds.height)
            return Window(id: id, frame: frame)
        }
        return WindowSnapshot(windows: windows)
    }

    /// The same windows with one more, such as the weather widget: in front of them all, or
    /// behind them.
    func including(_ frame: CGRect, id: CGWindowID, cornerRadius: CGFloat, inFront: Bool) -> WindowSnapshot {
        let window = Window(id: id, frame: frame, cornerRadius: cornerRadius)
        return WindowSnapshot(windows: inFront ? [window] + windows : windows + [window])
    }

    /// Whether a window fills this screen, as a full screen app does.
    func hasFullScreenWindow(on screen: CGRect) -> Bool {
        windows.contains { abs($0.frame.minX - screen.minX) < 1 && abs($0.frame.minY - screen.minY) < 1
            && abs($0.frame.width - screen.width) < 1 && abs($0.frame.height - screen.height) < 1 }
    }

    /// The parts of a window's top edge hidden by windows in front of it, as ranges of x.
    func coveredParts(ofTopOf index: Int) -> [ClosedRange<CGFloat>] {
        let top = windows[index].frame
        return windows[..<index].compactMap { front in
            // Covers the edge and a little above it, where a pile lies.
            guard front.frame.minY <= top.maxY + 2, front.frame.maxY > top.maxY - 1,
                  front.frame.maxX > top.minX, front.frame.minX < top.maxX
            else { return nil }
            return front.frame.minX...front.frame.maxX
        }
    }
}
