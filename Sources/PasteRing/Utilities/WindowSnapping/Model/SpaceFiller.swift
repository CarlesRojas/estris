import AppKit

/// Fits a snap to the windows already tiled on the screen: the snap's sides that aren't on
/// a screen edge move to the nearest edge of a neighbouring window, so the window fills the
/// space left instead of covering others or leaving a gap.
///
/// Only windows that look tiled count: on the same screen, touching a screen edge, and mostly
/// visible (not hidden behind others). The result never overlaps them; where the free space
/// isn't a rectangle it leaves the gap. Each direction may only grow or shrink so far from the
/// usual size (a third doesn't become two thirds), or it keeps the usual size.
@MainActor
enum SpaceFiller {
    /// How close edges must be to count as touching.
    private static let tolerance: CGFloat = 8
    /// How far, relative to the usual size, a direction may shrink or grow. Halves and
    /// corners may fill nearly the whole screen; thirds stay close to a third, so a lone third
    /// doesn't become two thirds.
    private static func sizeRange(for action: SnapAction) -> ClosedRange<CGFloat> {
        switch action.group {
        case .halves, .corners: 0.1...1.95
        default: 0.5...1.6
        }
    }
    /// Share of a window that must be uncovered for it to count.
    private static let minimumVisibleShare = 0.5

    /// The smallest size each app's windows took, learned when one refused to fit, so a
    /// later fill (and its preview) that would be smaller keeps the usual size.
    private static var minimumSizes: [pid_t: NSSize] = [:]

    /// The windows that count, in AppKit coordinates, leaving out `window`.
    static func tiledWindows(on screen: NSScreen, excluding window: AXWindow) -> [NSRect] {
        let area = screen.visibleFrame
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let windowFrame = window.frame
        // Front to back, the order the window server lists them in.
        var inFront: [NSRect] = []
        var tiled: [NSRect] = []
        for info in list {
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let cgRect = CGRect(dictionaryRepresentation: bounds as CFDictionary)
            else { continue }
            let frame = AXWindow.appKitRect(cgRect)
            if pid == window.pid, let windowFrame, nearlyEqual(frame, windowFrame) { continue }
            defer { inFront.append(frame) }
            let shared = frame.intersection(screen.frame)
            guard !shared.isNull, shared.width * shared.height > frame.width * frame.height / 2,
                  touchesEdge(frame, of: area),
                  visibleShare(of: frame, behind: inFront) >= minimumVisibleShare
            else { continue }
            tiled.append(frame)
        }
        return tiled
    }

    /// The snap's frame fitted to the tiled windows, or `usual` when nothing applies.
    static func fit(_ usual: NSRect, for action: SnapAction, on screen: NSScreen, among tiled: [NSRect], pid: pid_t) -> NSRect {
        guard ![.maximize, .center, .restore].contains(action), !tiled.isEmpty else { return usual }
        let area = screen.visibleFrame
        let freeLeft = usual.minX > area.minX + 1
        let freeRight = usual.maxX < area.maxX - 1
        let freeBottom = usual.minY > area.minY + 1
        let freeTop = usual.maxY < area.maxY - 1

        let range = sizeRange(for: action)
        var rect = usual
        // Twice, as moving the sides of one direction changes which windows the other meets.
        for _ in 0..<2 {
            rect = fitHorizontally(rect, usual: usual, freeLeft: freeLeft, freeRight: freeRight, among: tiled, range: range, area: area)
            rect = fitVertically(rect, usual: usual, freeBottom: freeBottom, freeTop: freeTop, among: tiled, range: range, area: area)
        }
        if let minimum = minimumSizes[pid], rect.width < minimum.width || rect.height < minimum.height {
            return usual
        }
        return rect
    }

    /// Whether a window refused the size it was asked for, ending up bigger; if so, its app's
    /// minimum is remembered.
    static func refused(asked: NSRect, got: NSRect?, pid: pid_t) -> Bool {
        guard let got, got.width > asked.width + 1 || got.height > asked.height + 1 else { return false }
        let known = minimumSizes[pid] ?? .zero
        minimumSizes[pid] = NSSize(width: max(known.width, got.width > asked.width + 1 ? got.width : 0),
                                   height: max(known.height, got.height > asked.height + 1 ? got.height : 0))
        return true
    }

    private static func fitHorizontally(_ rect: NSRect, usual: NSRect, freeLeft: Bool, freeRight: Bool, among tiled: [NSRect], range: ClosedRange<CGFloat>, area: NSRect) -> NSRect {
        let beside = tiled.filter { overlap($0.minY, $0.maxY, rect.minY, rect.maxY) > tolerance }
        var minX = rect.minX
        var maxX = rect.maxX
        // Vertical lines where other tiled windows' sides are, for a side with nothing beside it.
        let lines = tiled.flatMap { [$0.minX, $0.maxX] }.filter { $0 > area.minX + tolerance && $0 < area.maxX - tolerance }
        if freeLeft {
            if let edge = beside.filter({ $0.maxX < usual.maxX - tolerance && $0.minX < usual.minX + tolerance }).map(\.maxX).max() {
                minX = edge
            } else if let line = nearest(to: usual.minX, among: lines.filter { $0 < rect.maxX - tolerance }) {
                minX = line
            }
        }
        if freeRight {
            if let edge = beside.filter({ $0.minX > usual.minX + tolerance && $0.maxX > usual.maxX - tolerance }).map(\.minX).min() {
                maxX = edge
            } else if let line = nearest(to: usual.maxX, among: lines.filter { $0 > minX + tolerance }) {
                maxX = line
            }
        }
        guard range.contains((maxX - minX) / usual.width) else { return NSRect(x: usual.minX, y: rect.minY, width: usual.width, height: rect.height) }
        return NSRect(x: minX, y: rect.minY, width: maxX - minX, height: rect.height)
    }

    private static func fitVertically(_ rect: NSRect, usual: NSRect, freeBottom: Bool, freeTop: Bool, among tiled: [NSRect], range: ClosedRange<CGFloat>, area: NSRect) -> NSRect {
        let above = tiled.filter { overlap($0.minX, $0.maxX, rect.minX, rect.maxX) > tolerance }
        var minY = rect.minY
        var maxY = rect.maxY
        // Horizontal lines where other tiled windows' tops and bottoms are, for a side with
        // nothing above or below it.
        let lines = tiled.flatMap { [$0.minY, $0.maxY] }.filter { $0 > area.minY + tolerance && $0 < area.maxY - tolerance }
        if freeBottom {
            if let edge = above.filter({ $0.maxY < usual.maxY - tolerance && $0.minY < usual.minY + tolerance }).map(\.maxY).max() {
                minY = edge
            } else if let line = nearest(to: usual.minY, among: lines.filter { $0 < rect.maxY - tolerance }) {
                minY = line
            }
        }
        if freeTop {
            if let edge = above.filter({ $0.minY > usual.minY + tolerance && $0.maxY > usual.maxY - tolerance }).map(\.minY).min() {
                maxY = edge
            } else if let line = nearest(to: usual.maxY, among: lines.filter { $0 > minY + tolerance }) {
                maxY = line
            }
        }
        guard range.contains((maxY - minY) / usual.height) else { return NSRect(x: rect.minX, y: usual.minY, width: rect.width, height: usual.height) }
        return NSRect(x: rect.minX, y: minY, width: rect.width, height: maxY - minY)
    }

    private static func nearest(to value: CGFloat, among lines: [CGFloat]) -> CGFloat? {
        lines.min { abs($0 - value) < abs($1 - value) }
    }

    private static func nearlyEqual(_ a: NSRect, _ b: NSRect) -> Bool {
        abs(a.minX - b.minX) < 2 && abs(a.minY - b.minY) < 2 && abs(a.width - b.width) < 2 && abs(a.height - b.height) < 2
    }

    private static func overlap(_ a1: CGFloat, _ a2: CGFloat, _ b1: CGFloat, _ b2: CGFloat) -> CGFloat {
        min(a2, b2) - max(a1, b1)
    }

    private static func touchesEdge(_ frame: NSRect, of area: NSRect) -> Bool {
        abs(frame.minX - area.minX) <= tolerance || abs(frame.maxX - area.maxX) <= tolerance
            || abs(frame.minY - area.minY) <= tolerance || abs(frame.maxY - area.maxY) <= tolerance
    }

    /// The share of a window not covered by the windows in front of it, sampled on a grid.
    private static func visibleShare(of frame: NSRect, behind inFront: [NSRect]) -> Double {
        guard !inFront.isEmpty else { return 1 }
        let steps = 6
        var visible = 0
        for column in 0..<steps {
            for row in 0..<steps {
                let point = NSPoint(x: frame.minX + frame.width * (CGFloat(column) + 0.5) / CGFloat(steps),
                                    y: frame.minY + frame.height * (CGFloat(row) + 0.5) / CGFloat(steps))
                if !inFront.contains(where: { $0.contains(point) }) { visible += 1 }
            }
        }
        return Double(visible) / Double(steps * steps)
    }
}
