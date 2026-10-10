import AppKit
import Carbon.HIToolbox

/// Arrange All (⌃⌥Space): every window on a screen shares it evenly. Two side by side, three in thirds,
/// four in quarters; from five on, columns (about the square root of the count) with the
/// windows spread over them, the fewer per column on the left. Five is a left third plus four
/// quarters of the rest, six is three columns of two, seven is 2 + 2 + 3, and so on. Each
/// window goes to the space nearest where it is, so what is on the left stays on the left.
enum WindowArranger {
    /// Control, Option and Space, like the other snap shortcuts.
    static var shortcut: Shortcut {
        Shortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey), keyLabel: String(localized: "Space"))
    }

    /// macOS uses ⌃⌥Space to switch to the next input source, and keeps it while that shortcut
    /// is on: Arrange All only gets the keys once it's turned off.
    static var isShortcutTaken: Bool {
        SystemShortcuts.isTaken(keyCode: CGKeyCode(kVK_Space), flags: [.maskControl, .maskAlternate], by: SystemShortcuts.selectNextInputSource)
    }

    /// The windows mostly on the screen: normal windows of regular apps (and
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

    /// Which frame each window gets: the pairing that moves them least in all, measuring
    /// between centres in proportion to the area, so a window further left ends up on the left,
    /// a higher one higher. `result[i]` is the frame for `windows[i]`.
    static func assign(_ windows: [NSRect], to frames: [NSRect], in area: NSRect) -> [NSRect] {
        let count = min(windows.count, frames.count)
        guard count > 0 else { return [] }
        func center(_ rect: NSRect) -> (CGFloat, CGFloat) {
            ((rect.midX - area.minX) / max(area.width, 1), (rect.midY - area.minY) / max(area.height, 1))
        }
        let cost = (0..<count).map { row in
            (0..<count).map { column -> Double in
                let (wx, wy) = center(windows[row])
                let (fx, fy) = center(frames[column])
                return Double((wx - fx) * (wx - fx) + (wy - fy) * (wy - fy))
            }
        }
        return hungarian(cost).map { frames[$0] }
    }

    /// The cheapest pairing of rows with columns of a square cost matrix (Kuhn and Munkres):
    /// the column for each row.
    private static func hungarian(_ cost: [[Double]]) -> [Int] {
        let n = cost.count
        var u = [Double](repeating: 0, count: n + 1)
        var v = [Double](repeating: 0, count: n + 1)
        var match = [Int](repeating: 0, count: n + 1) // column -> row, 1-based
        var way = [Int](repeating: 0, count: n + 1)
        for row in 1...n {
            match[0] = row
            var column0 = 0
            var minimum = [Double](repeating: .infinity, count: n + 1)
            var used = [Bool](repeating: false, count: n + 1)
            repeat {
                used[column0] = true
                let row0 = match[column0]
                var delta = Double.infinity
                var column1 = 0
                for column in 1...n where !used[column] {
                    let current = cost[row0 - 1][column - 1] - u[row0] - v[column]
                    if current < minimum[column] {
                        minimum[column] = current
                        way[column] = column0
                    }
                    if minimum[column] < delta {
                        delta = minimum[column]
                        column1 = column
                    }
                }
                for column in 0...n {
                    if used[column] {
                        u[match[column]] += delta
                        v[column] -= delta
                    } else {
                        minimum[column] -= delta
                    }
                }
                column0 = column1
            } while match[column0] != 0
            repeat {
                let column1 = way[column0]
                match[column0] = match[column1]
                column0 = column1
            } while column0 != 0
        }
        var result = [Int](repeating: 0, count: n)
        for column in 1...n where match[column] > 0 {
            result[match[column] - 1] = column - 1
        }
        return result
    }

    /// One frame per window: left column first, top to bottom.
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
