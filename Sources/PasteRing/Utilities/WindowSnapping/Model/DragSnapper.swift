import AppKit

/// Watches the mouse to snap windows dragged to a screen edge or corner, and to resize the
/// windows next to one being resized.
///
/// A drag starts on a window; once it moves without changing size it is being moved, and
/// the pointer's place on the screen picks a snap area (previewed, applied on release).
/// Once its size changes it is being resized, and windows that shared the edge being dragged
/// follow it.
@MainActor
final class DragSnapper {
    /// How far into the screen an edge reaches. Wider than the screen's very edge, so a
    /// drag can stop on an edge shared with another display.
    private static let edgeBand: CGFloat = 32
    /// How far along an edge from a corner the corner reaches.
    private static let cornerLength: CGFloat = 64
    /// How far along a side edge from its ends the top and bottom halves reach.
    private static let shortEdgeLength: CGFloat = 145
    /// How close edges must be to count as shared.
    private static let sharedEdgeTolerance: CGFloat = 4
    /// Smallest size a neighbour is resized down to.
    private static let minimumNeighbourSize: CGFloat = 120
    /// Gap between window reads while dragging.
    private static let readInterval: TimeInterval = 1.0 / 30

    private enum Mode { case undecided, moving, resizing }

    /// A window sharing an edge with the one being resized, and which edge.
    private struct Neighbour {
        let window: AXWindow
        let frame: NSRect
        let edge: Edge
    }

    private enum Edge { case left, right, top, bottom }

    private let settings: WindowSnappingSettings
    private let snapper: (AXWindow, SnapAction, NSScreen, NSRect) -> Void
    private let preview = SnapPreview()
    private var monitors: [Any] = []

    private var window: AXWindow?
    private var startFrame: NSRect = .zero
    private var mode = Mode.undecided
    private var lastRead = Date.distantPast
    private var target: (action: SnapAction, screen: NSScreen)?
    private var neighbours: [Neighbour]?

    init(settings: WindowSnappingSettings, snapper: @escaping (AXWindow, SnapAction, NSScreen, NSRect) -> Void) {
        self.settings = settings
        self.snapper = snapper
    }

    func start() {
        guard monitors.isEmpty else { return }
        let handlers: [(NSEvent.EventTypeMask, (NSEvent) -> Void)] = [
            (.leftMouseDown, { [weak self] _ in self?.mouseDown() }),
            (.leftMouseDragged, { [weak self] _ in self?.mouseDragged() }),
            (.leftMouseUp, { [weak self] _ in self?.mouseUp() }),
        ]
        // Global monitors run on the main thread.
        monitors = handlers.compactMap { mask, handler in
            NSEvent.addGlobalMonitorForEvents(matching: mask) { event in
                MainActor.assumeIsolated { handler(event) }
            }
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        reset()
    }

    private func mouseDown() {
        reset()
        guard let window = AXWindow.at(NSEvent.mouseLocation), window.pid != getpid(), let frame = window.frame else { return }
        self.window = window
        startFrame = frame
    }

    private func mouseDragged() {
        guard let window, Date().timeIntervalSince(lastRead) >= Self.readInterval else { return }
        lastRead = Date()
        if mode == .undecided {
            guard let frame = window.frame, frame != startFrame else { return }
            mode = frame.size == startFrame.size ? .moving : .resizing
        }
        switch mode {
        case .moving:
            guard settings.snapsByDragging else { return }
            updateTarget()
        case .resizing:
            guard settings.resizesTogether, let frame = window.frame else { return }
            resizeNeighbours(to: frame)
        case .undecided:
            break
        }
    }

    private func mouseUp() {
        defer { reset() }
        guard let window else { return }
        switch mode {
        case .moving:
            if let target { snapper(window, target.action, target.screen, startFrame) }
        case .resizing:
            // The last drag events may have been skipped; line the neighbours up once more.
            if settings.resizesTogether, let frame = window.frame { resizeNeighbours(to: frame) }
        case .undecided:
            break
        }
    }

    private func reset() {
        window = nil
        mode = .undecided
        target = nil
        neighbours = nil
        preview.hide()
    }

    // MARK: - Snap areas

    private func updateTarget() {
        let point = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }),
              let found = snapArea(at: point, on: screen.frame),
              let window, let current = window.frame,
              let area = found.action.frame(in: screen, current: current)
        else {
            target = nil
            preview.hide()
            return
        }
        target = (found.action, screen)
        preview.show(area, from: found.edge)
    }

    /// The snap area under the pointer: corners for quarters, the top for the whole screen,
    /// the sides for halves (top and bottom halves near their ends), and the bottom for
    /// thirds, which become two thirds when the drag slides from a side third to the middle.
    private func snapArea(at point: NSPoint, on frame: NSRect) -> (action: SnapAction, edge: SnapEdge)? {
        let band = Self.edgeBand
        let corner = Self.cornerLength
        let left = point.x <= frame.minX + band
        let right = point.x >= frame.maxX - band
        let top = point.y >= frame.maxY - band
        let bottom = point.y <= frame.minY + band
        let nearLeft = point.x <= frame.minX + corner
        let nearRight = point.x >= frame.maxX - corner
        let nearTop = point.y >= frame.maxY - corner
        let nearBottom = point.y <= frame.minY + corner

        if (left && nearTop) || (top && nearLeft) { return (.topLeft, .topLeft) }
        if (right && nearTop) || (top && nearRight) { return (.topRight, .topRight) }
        if (left && nearBottom) || (bottom && nearLeft) { return (.bottomLeft, .bottomLeft) }
        if (right && nearBottom) || (bottom && nearRight) { return (.bottomRight, .bottomRight) }
        if top { return (.maximize, .top) }
        if left || right {
            let edge: SnapEdge = left ? .left : .right
            if point.y >= frame.maxY - Self.shortEdgeLength { return (.topHalf, edge) }
            if point.y <= frame.minY + Self.shortEdgeLength { return (.bottomHalf, edge) }
            return (left ? .leftHalf : .rightHalf, edge)
        }
        if bottom {
            let third = frame.width / 3
            if point.x < frame.minX + third { return (.firstThird, .bottom) }
            if point.x > frame.maxX - third { return (.lastThird, .bottom) }
            switch target?.action {
            case .firstThird, .firstTwoThirds: return (.firstTwoThirds, .bottom)
            case .lastThird, .lastTwoThirds: return (.lastTwoThirds, .bottom)
            default: return (.centerThird, .bottom)
            }
        }
        return nil
    }

    // MARK: - Resizing together

    private func resizeNeighbours(to frame: NSRect) {
        if neighbours == nil { neighbours = findNeighbours(movedTo: frame) }
        for neighbour in neighbours ?? [] {
            var rect = neighbour.frame
            switch neighbour.edge {
            case .right:
                // The window's right edge moved; the neighbour on its right keeps its own right edge.
                rect = NSRect(x: frame.maxX, y: rect.minY, width: neighbour.frame.maxX - frame.maxX, height: rect.height)
            case .left:
                rect.size.width = frame.minX - neighbour.frame.minX
            case .top:
                rect = NSRect(x: rect.minX, y: frame.maxY, width: rect.width, height: neighbour.frame.maxY - frame.maxY)
            case .bottom:
                rect.size.height = frame.minY - neighbour.frame.minY
            }
            guard rect.width >= Self.minimumNeighbourSize, rect.height >= Self.minimumNeighbourSize else { continue }
            neighbour.window.setFrame(rect)
        }
    }

    /// Windows that shared each edge the resize moved, found once per drag.
    private func findNeighbours(movedTo frame: NSRect) -> [Neighbour] {
        let tolerance = Self.sharedEdgeTolerance
        var moved: [Edge] = []
        if abs(frame.minX - startFrame.minX) > 0.5 { moved.append(.left) }
        if abs(frame.maxX - startFrame.maxX) > 0.5 { moved.append(.right) }
        if abs(frame.maxY - startFrame.maxY) > 0.5 { moved.append(.top) }
        if abs(frame.minY - startFrame.minY) > 0.5 { moved.append(.bottom) }
        guard !moved.isEmpty, let window else { return [] }

        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var found: [Neighbour] = []
        for info in list {
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let cgRect = CGRect(dictionaryRepresentation: bounds as CFDictionary)
            else { continue }
            let other = AXWindow.appKitRect(cgRect)
            if pid == window.pid, other == startFrame { continue }
            let overlapsVertically = other.minY < startFrame.maxY - tolerance && other.maxY > startFrame.minY + tolerance
            let overlapsHorizontally = other.minX < startFrame.maxX - tolerance && other.maxX > startFrame.minX + tolerance
            for edge in moved {
                let shares: Bool = switch edge {
                case .right: overlapsVertically && abs(other.minX - startFrame.maxX) <= tolerance
                case .left: overlapsVertically && abs(other.maxX - startFrame.minX) <= tolerance
                case .top: overlapsHorizontally && abs(other.minY - startFrame.maxY) <= tolerance
                case .bottom: overlapsHorizontally && abs(other.maxY - startFrame.minY) <= tolerance
                }
                if shares, let neighbour = AXWindow.of(pid: pid, matching: other) {
                    found.append(Neighbour(window: neighbour, frame: other, edge: edge))
                }
            }
        }
        return found
    }
}
