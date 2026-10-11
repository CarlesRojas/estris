import AppKit
import Carbon.HIToolbox

/// Arrange All (⌃⌥Space unless changed): every window on a screen shares it evenly. Two side by side, three in thirds,
/// four in quarters; from five on, columns (about the square root of the count) with the
/// windows spread over them, the fewer per column on the left. Five is a left third plus four
/// quarters of the rest, six is three columns of two, seven is 2 + 2 + 3, and so on. Each
/// window goes to the space nearest where it is, so what is on the left stays on the left.
/// An app that can't get as wide or tall as its share takes what it can, and the others
/// share the rest.
enum WindowArranger {
    /// The windows mostly on the screen: normal windows of regular apps (and
    /// Estris's own), not minimized or hidden ones.
    static func windows(on screen: NSScreen) -> [AXWindow] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let found = list.compactMap { info -> AXWindow? in
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let number = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular || pid == getpid(),
                  (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let cgRect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  cgRect.width >= 100, cgRect.height >= 60
            else { return nil }
            let frame = AXWindow.appKitRect(cgRect)
            let shared = frame.intersection(screen.frame)
            guard !shared.isNull, shared.width * shared.height > frame.width * frame.height / 2 else { return nil }
            return AXWindow.of(pid: pid, number: number, frame: frame)
        }
        // Matching by frame can find the same window twice.
        return found.enumerated().filter { index, window in
            !found[..<index].contains { $0.isSame(as: window) }
        }.map(\.element)
    }

    /// Which space each window gets: the pairing that moves them least in all, measuring
    /// between centres in proportion to the area, so a window further left ends up on the left,
    /// a higher one higher. `result[i]` is the index in `frames` for `windows[i]`.
    static func assign(_ windows: [NSRect], to frames: [NSRect], in area: NSRect) -> [Int] {
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
        return hungarian(cost)
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

    /// How many windows each column gets, left to right; the extra ones go to the right-hand
    /// columns.
    static func columns(count: Int) -> [Int] {
        guard count > 0 else { return [] }
        let columns = count <= 3 ? count : Int(Double(count).squareRoot().rounded(.up))
        let base = count / columns
        let extra = count % columns
        return (0..<columns).map { base + ($0 >= columns - extra ? 1 : 0) }
    }

    /// One frame per window, column by column, each from the top down. Space is shared
    /// evenly, except that a window that can't get as wide or as tall as its share (an app
    /// with a maximum size) takes only what it can, and the others share the rest. A column is
    /// as wide as its widest window can be. `maxWidths` and `maxHeights` are per window, in
    /// the same order; infinity when there is no limit.
    static func frames(columns: [Int], in area: NSRect, maxWidths: [[CGFloat]]? = nil, maxHeights: [[CGFloat]]? = nil) -> [[NSRect]] {
        let widths = share(area.width, maximums: columns.indices.map { maxWidths?[$0].max() ?? .infinity })
        var minX = area.minX
        return columns.enumerated().map { column, rows in
            let heights = share(area.height, maximums: maxHeights?[column] ?? Array(repeating: .infinity, count: rows))
            let left = minX.rounded()
            minX += widths[column]
            let right = minX.rounded()
            var maxY = area.maxY
            return (0..<rows).map { row in
                let top = maxY.rounded()
                maxY -= heights[row]
                let bottom = maxY.rounded()
                return NSRect(x: left, y: bottom, width: right - left, height: top - bottom)
            }
        }
    }

    /// Splits a length as evenly as the parts' maximums allow: a part whose maximum is under
    /// an even share gets its maximum, and the others share what is left. When every part has
    /// reached its maximum, the rest stays empty, at the end.
    static func share(_ length: CGFloat, maximums: [CGFloat]) -> [CGFloat] {
        var sizes = maximums.map { _ in CGFloat(0) }
        var open = Array(maximums.indices)
        var left = length
        while !open.isEmpty {
            let even = left / CGFloat(open.count)
            let capped = open.filter { maximums[$0] < even }
            guard !capped.isEmpty else {
                for index in open { sizes[index] = even }
                break
            }
            for index in capped {
                sizes[index] = maximums[index]
                left -= maximums[index]
            }
            open.removeAll { capped.contains($0) }
        }
        return sizes
    }
}
