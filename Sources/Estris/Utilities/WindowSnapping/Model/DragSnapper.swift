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
    /// How far along an edge from a corner the corner reaches, at least.
    private static let minimumCornerLength: CGFloat = 64
    /// How far along a side edge from its ends the top and bottom halves reach.
    private static let shortEdgeLength: CGFloat = 145
    /// How close edges must be to count as shared.
    private static let sharedEdgeTolerance: CGFloat = 4
    /// Smallest size a neighbour is resized down to.
    private static let minimumNeighbourSize: CGFloat = 120
    /// How tall the title bar and toolbar of Estris's windows are, where they are dragged.
    private static let ownTitleBarHeight: CGFloat = 52
    /// Gap between window reads while dragging.
    private static let readInterval: TimeInterval = 1.0 / 30

    private enum Mode { case undecided, moving, resizing }

    /// A window with edges on the lines being dragged.
    private struct Neighbour {
        let window: AXWindow
        let frame: NSRect
        /// Its edges on the lines, and the line each is on.
        let edges: [(edge: Edge, line: Line)]
    }

    private enum Edge { case left, right, top, bottom }

    /// A vertical (x) or horizontal (y) line across the screen, where the dragged edge was.
    private struct Line {
        let isVertical: Bool
        let position: CGFloat
        /// Which edge of the dragged window lies on it.
        let draggedEdge: Edge
    }

    private let settings: WindowSnappingSettings
    /// Snaps a window: the action, its screen, where the window started, and whether to fill
    /// the space next to other windows.
    private let snapper: (AXWindow, SnapAction, NSScreen, NSRect, Bool) -> Void
    private let preview = SnapPreview()
    private var tap: CFMachPort?

    private var window: AXWindow?
    private var startFrame: NSRect = .zero
    private var startPoint: NSPoint = .zero
    private var mode = Mode.undecided
    private var lastRead = Date.distantPast
    private var target: (action: SnapAction, screen: NSScreen)?
    private var neighbours: [Neighbour]?
    /// The tiled windows on each screen the drag has passed over, for filling space.
    private var tiled: [NSScreen: [NSRect]] = [:]

    init(settings: WindowSnappingSettings, snapper: @escaping (AXWindow, SnapAction, NSScreen, NSRect, Bool) -> Void) {
        self.settings = settings
        self.snapper = snapper
    }

    /// A listen-only event tap: unlike a global event monitor, it also sees drags of
    /// Estris's own windows.
    func start() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: true)
            return
        }
        let types: [CGEventType] = [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .flagsChanged]
        tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: types.reduce(CGEventMask(0)) { $0 | 1 << $1.rawValue },
            callback: dragSnapperCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        guard let tap else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        reset()
    }

    /// Whether ⌘ is held, which snaps to the exact area without filling space.
    private var isExact = false

    /// Fills the space next to other windows unless off in Settings or ⌘ is held.
    private var fills: Bool {
        settings.fillsSpace && !isExact
    }

    fileprivate func handle(_ type: CGEventType, flags: CGEventFlags) {
        isExact = flags.contains(.maskCommand)
        switch type {
        case .flagsChanged:
            // Pressing or letting go of ⌘ mid-drag switches the preview at once.
            if mode == .moving, settings.snapsByDragging { updateTarget() }
        case .leftMouseDown: mouseDown()
        case .leftMouseDragged: mouseDragged()
        case .leftMouseUp: mouseUp()
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        default: break
        }
    }

    private func mouseDown() {
        reset()
        // Windows kept in front of everything are left alone, and don't drag others along.
        guard let window = AXWindow.at(NSEvent.mouseLocation), let frame = window.frame, window.isNormalLevel else { return }
        self.window = window
        startFrame = frame
        startPoint = NSEvent.mouseLocation
    }

    private func mouseDragged() {
        guard let window, Date().timeIntervalSince(lastRead) >= Self.readInterval else { return }
        lastRead = Date()
        if mode == .undecided {
            guard let frame = window.frame else { return }
            if frame != startFrame {
                mode = frame.size == startFrame.size ? .moving : .resizing
            } else if isDraggingOwnTitleBar {
                mode = .moving
            } else {
                return
            }
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
            if let target { snapper(window, target.action, target.screen, startFrame, fills) }
        case .resizing:
            // The last drag events may have been skipped; line the neighbours up once more.
            if settings.resizesTogether, let frame = window.frame { resizeNeighbours(to: frame) }
        case .undecided:
            break
        }
    }

    /// Estris's own windows may only report their new place once the drag ends, so a drag
    /// that started in the title bar area and has gone a few points counts as moving.
    private var isDraggingOwnTitleBar: Bool {
        guard window?.own != nil else { return false }
        let point = NSEvent.mouseLocation
        return startFrame.maxY - startPoint.y <= Self.ownTitleBarHeight
            && hypot(point.x - startPoint.x, point.y - startPoint.y) > 3
    }

    private func reset() {
        window = nil
        mode = .undecided
        target = nil
        neighbours = nil
        tiled = [:]
        preview.hide()
    }

    // MARK: - Snap areas

    private func updateTarget() {
        let point = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }),
              let found = snapArea(at: point, on: screen.frame),
              let window, let current = window.frame,
              let usual = found.action.frame(in: screen, current: current)
        else {
            target = nil
            preview.hide()
            return
        }
        var area = usual
        if fills {
            if tiled[screen] == nil { tiled[screen] = SpaceFiller.tiledWindows(on: screen, excluding: window) }
            area = SpaceFiller.fit(usual, for: found.action, on: screen, among: tiled[screen] ?? [], pid: window.pid)
        }
        target = (found.action, screen)
        preview.show(area, from: found.edge, isFrosted: settings.frostedPreview)
    }

    /// The snap area under the pointer: corners for quarters, the top for the whole screen,
    /// the sides for halves (top and bottom halves near their ends), and the bottom for
    /// thirds, which become two thirds when the drag slides from a side third to the middle.
    /// Gestures switched off in Settings leave their place to the next area that applies.
    /// The edges reach as far into the screen as Settings says, wider than the screen's very
    /// edge, so a drag can stop on an edge shared with another display.
    private func snapArea(at point: NSPoint, on frame: NSRect) -> (action: SnapAction, edge: SnapEdge)? {
        let on = settings.gestures
        let band = CGFloat(settings.edgeArea)
        let corner = max(Self.minimumCornerLength, band)
        let left = point.x <= frame.minX + band
        let right = point.x >= frame.maxX - band
        let top = point.y >= frame.maxY - band
        let bottom = point.y <= frame.minY + band
        let nearLeft = point.x <= frame.minX + corner
        let nearRight = point.x >= frame.maxX - corner
        let nearTop = point.y >= frame.maxY - corner
        let nearBottom = point.y <= frame.minY + corner

        if on.contains(.topLeft), (left && nearTop) || (top && nearLeft) { return (.topLeft, .topLeft) }
        if on.contains(.topRight), (right && nearTop) || (top && nearRight) { return (.topRight, .topRight) }
        if on.contains(.bottomLeft), (left && nearBottom) || (bottom && nearLeft) { return (.bottomLeft, .bottomLeft) }
        if on.contains(.bottomRight), (right && nearBottom) || (bottom && nearRight) { return (.bottomRight, .bottomRight) }
        if top, on.contains(.maximize) { return (.maximize, .top) }
        if left || right {
            let edge: SnapEdge = left ? .left : .right
            if on.contains(.topHalf), point.y >= frame.maxY - Self.shortEdgeLength { return (.topHalf, edge) }
            if on.contains(.bottomHalf), point.y <= frame.minY + Self.shortEdgeLength { return (.bottomHalf, edge) }
            if left, on.contains(.leftHalf) { return (.leftHalf, edge) }
            if right, on.contains(.rightHalf) { return (.rightHalf, edge) }
        }
        if bottom, on.contains(.thirds) {
            let third = frame.width / 3
            if point.x < frame.minX + third { return (.firstThird, .bottom) }
            if point.x > frame.maxX - third { return (.lastThird, .bottom) }
            guard on.contains(.twoThirds) else { return (.centerThird, .bottom) }
            switch target?.action {
            case .firstThird, .firstTwoThirds: return (.firstTwoThirds, .bottom)
            case .lastThird, .lastTwoThirds: return (.lastTwoThirds, .bottom)
            default: return (.centerThird, .bottom)
            }
        }
        return nil
    }

    // MARK: - Resizing together

    /// Moves every window edge that lay on a line the resize moved, so windows tiled along
    /// that line, on either side and anywhere along it, keep meeting there.
    private func resizeNeighbours(to frame: NSRect) {
        if neighbours == nil { neighbours = findNeighbours(movedTo: frame) }
        for neighbour in neighbours ?? [] {
            var rect = neighbour.frame
            for (edge, line) in neighbour.edges {
                let position = self.position(of: line, in: frame)
                switch edge {
                case .left: rect = NSRect(x: position, y: rect.minY, width: rect.maxX - position, height: rect.height)
                case .right: rect.size.width = position - rect.minX
                case .bottom: rect = NSRect(x: rect.minX, y: position, width: rect.width, height: rect.maxY - position)
                case .top: rect.size.height = position - rect.minY
                }
            }
            guard rect.width >= Self.minimumNeighbourSize, rect.height >= Self.minimumNeighbourSize else { continue }
            neighbour.window.setFrame(rect)
        }
    }

    /// Where the dragged window's edge that was on a line is now.
    private func position(of line: Line, in frame: NSRect) -> CGFloat {
        switch line.draggedEdge {
        case .left: frame.minX
        case .right: frame.maxX
        case .bottom: frame.minY
        case .top: frame.maxY
        }
    }

    /// Every other window on the same screen with an edge on a line the resize moved, found
    /// once per drag.
    private func findNeighbours(movedTo frame: NSRect) -> [Neighbour] {
        let tolerance = Self.sharedEdgeTolerance
        var lines: [Line] = []
        if abs(frame.minX - startFrame.minX) > 0.5 { lines.append(Line(isVertical: true, position: startFrame.minX, draggedEdge: .left)) }
        if abs(frame.maxX - startFrame.maxX) > 0.5 { lines.append(Line(isVertical: true, position: startFrame.maxX, draggedEdge: .right)) }
        if abs(frame.minY - startFrame.minY) > 0.5 { lines.append(Line(isVertical: false, position: startFrame.minY, draggedEdge: .bottom)) }
        if abs(frame.maxY - startFrame.maxY) > 0.5 { lines.append(Line(isVertical: false, position: startFrame.maxY, draggedEdge: .top)) }
        guard !lines.isEmpty, let window, let screen = window.screen?.frame else { return [] }

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
            // Mostly on the same screen.
            let shared = other.intersection(screen)
            guard !shared.isNull, shared.width * shared.height > other.width * other.height / 2 else { continue }
            var edges: [(edge: Edge, line: Line)] = []
            for line in lines {
                let near = { (value: CGFloat) in abs(value - line.position) <= tolerance }
                if line.isVertical {
                    if near(other.minX) { edges.append((.left, line)) }
                    if near(other.maxX) { edges.append((.right, line)) }
                } else {
                    if near(other.minY) { edges.append((.bottom, line)) }
                    if near(other.maxY) { edges.append((.top, line)) }
                }
            }
            guard !edges.isEmpty, let neighbour = AXWindow.of(pid: pid, matching: other) else { continue }
            found.append(Neighbour(window: neighbour, frame: other, edges: edges))
        }
        return found
    }
}

/// Plain C function for the event tap; the snapper comes back through the refcon. Runs on
/// the main run loop, where the tap is scheduled.
private func dragSnapperCallback(
    _ proxy: CGEventTapProxy,
    _ type: CGEventType,
    _ event: CGEvent,
    _ refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if let refcon {
        let snapper = Unmanaged<DragSnapper>.fromOpaque(refcon).takeUnretainedValue()
        let flags = event.flags
        MainActor.assumeIsolated { snapper.handle(type, flags: flags) }
    }
    return Unmanaged.passUnretained(event)
}

