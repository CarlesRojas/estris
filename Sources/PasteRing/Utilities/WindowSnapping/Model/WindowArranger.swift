import AppKit
import Carbon.HIToolbox

/// Arrange All: every window on a screen shares it evenly. Two side by side, three in thirds,
/// four in quarters; from five on, columns (about the square root of the count) with the
/// windows spread over them, the fewer per column on the left, so the front windows get the
/// bigger spaces. Five is a left third plus four quarters of the rest, six is three columns of
/// two, seven is 2 + 2 + 3, and so on.
enum WindowArranger {
    /// Control, Option and A, like the other snap shortcuts.
    static let shortcut = Shortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(controlKey | optionKey), keyLabel: "A")

    /// The windows mostly on the screen, front to back: normal windows of regular apps (and
    /// PasteRing's own), not minimized or hidden ones.
    static func windows(on screen: NSScreen) -> [AXWindow] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var seen: [NSRect] = []
        return list.compactMap { info -> AXWindow? in
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular || pid == getpid(),
                  (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let cgRect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  cgRect.width >= 100, cgRect.height >= 60
            else { return nil }
            let frame = AXWindow.appKitRect(cgRect)
            let shared = frame.intersection(screen.frame)
            guard !shared.isNull, shared.width * shared.height > frame.width * frame.height / 2,
                  !seen.contains(frame)
            else { return nil }
            seen.append(frame)
            return AXWindow.of(pid: pid, matching: frame)
        }
    }

    /// One frame per window, in the order to hand them out: left column first, top to bottom.
    static func frames(count: Int, in area: NSRect) -> [NSRect] {
        guard count > 0 else { return [] }
        let columns = count <= 3 ? count : Int(Double(count).squareRoot().rounded(.up))
        let base = count / columns
        let extra = count % columns
        var frames: [NSRect] = []
        for column in 0..<columns {
            // The extra windows go to the right-hand columns.
            let rows = base + (column >= columns - extra ? 1 : 0)
            let minX = (area.minX + area.width * CGFloat(column) / CGFloat(columns)).rounded()
            let maxX = (area.minX + area.width * CGFloat(column + 1) / CGFloat(columns)).rounded()
            for row in 0..<rows {
                // From the top down.
                let maxY = (area.maxY - area.height * CGFloat(row) / CGFloat(rows)).rounded()
                let minY = (area.maxY - area.height * CGFloat(row + 1) / CGFloat(rows)).rounded()
                frames.append(NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY))
            }
        }
        return frames
    }
}
