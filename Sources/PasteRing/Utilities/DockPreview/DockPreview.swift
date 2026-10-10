import AppKit
import Combine
import SwiftUI

/// The Dock Preview utility: resting the pointer on a running app's Dock icon shows its windows
/// as thumbnails in a frosted panel next to the icon; a click brings one forward, its × closes
/// it. Needs macOS 14 or later (for window thumbnails); on older versions its pane is hidden and
/// it never starts. Owns everything it needs, so the app only has to create it and call
/// `start()`.
@MainActor
final class DockPreview {
    static var isSupported: Bool {
        if #available(macOS 14, *) { return true }
        return false
    }

    /// Room around the panel's content for its shadow.
    private static let shadowRoom: CGFloat = 24
    /// Between the Dock icon and the panel.
    private static let gap: CGFloat = 6
    /// How long the pointer may be away from the icon and the panel before it closes, so it
    /// can cut a corner on the way up to the panel.
    private static let hideDelay: TimeInterval = 0.3

    /// Developer > Settings: draws the area that keeps the panel open, to tune it.
    static let showsAreaKey = "developerShowsDockPreviewArea"

    let settings = DockPreviewSettings()
    private let state = DockPreviewState()
    private let appLog: AppLog
    private var observers: Set<AnyCancellable> = []
    private var tap: CFMachPort?
    /// While the panel shows: the scroll wheel picks a window, Return opens it, Esc closes.
    private var inputTap: CFMachPort?
    /// Scroll from a trackpad, gathered until it is enough for one step.
    private var scrolled: CGFloat = 0
    /// Brings the highlighted window forward once scrolling pauses.
    private var pendingFocus: DispatchWorkItem?
    /// Desktop changes until then come from scrolling, not the user leaving.
    private var keepThroughDesktopChangesUntil = Date.distantPast
    private var spaceObserver: NSObjectProtocol?
    private var layout = DockLayout.current()
    private var layoutRead = Date.distantPast
    private var pendingOpen: (pid: pid_t, work: DispatchWorkItem)?
    private var pendingHide: DispatchWorkItem?
    private var panel: NSPanel?
    /// The icon whose windows are showing, and where the panel's content is.
    private var shown: DockItem?
    private var contentFrame: NSRect = .zero
    private var captureTask: Task<Void, Never>?
    /// The app whose Dock icon was just clicked: its preview waits until the pointer leaves the
    /// icon and comes back, so it doesn't cover the Dock's menu or a launching app.
    private var clickedPID: pid_t?
    /// Where the pointer last was on the shown app's icon: the tip of the way up to the panel.
    private var lastOnIcon: NSPoint?
    /// The debugging drawing of that area, when turned on in Developer settings.
    private var areaPanel: NSPanel?
    /// The last thumbnail of each window, shown at once the next time.
    private var thumbnailCache: [CGWindowID: CGImage] = [:]

    init(log: AppLog) {
        appLog = log
    }

    func start() {
        guard Self.isSupported else { return }
        // PasteRing quit while it held the Dock showing: let it hide itself again.
        DockHold.end()
        settings.$isEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in self?.setActive(enabled) }
            .store(in: &observers)
    }

    /// The pane shown for this utility in Settings.
    func settingsPane() -> some View {
        DockPreviewPane(settings: settings)
    }

    private func setActive(_ active: Bool) {
        hide()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
        spaceObserver = nil
        guard active else {
            thumbnailCache = [:]
            return
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        } else {
            let types: [CGEventType] = [.mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown]
            tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .tailAppendEventTap,
                options: .listenOnly,
                eventsOfInterest: types.reduce(CGEventMask(0)) { $0 | 1 << $1.rawValue },
                callback: dockPreviewCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
            guard let tap else { return log("can't watch the pointer; needs Accessibility access") }
            CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                // Scrolling through windows travels between desktops on purpose; the panel stays.
                guard let self, Date() >= self.keepThroughDesktopChangesUntil else { return }
                self.hide()
            }
        }
    }

    fileprivate func handle(_ type: CGEventType) {
        switch type {
        case .mouseMoved:
            pointerMoved(NSEvent.mouseLocation)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            cancelOpen()
            let point = NSEvent.mouseLocation
            if !contentFrame.contains(point), layout.isNear(point), let item = DockItems.item(at: point) {
                clickedPID = item.app.processIdentifier
            }
            // A click on the Dock or elsewhere closes it; one in the panel is the panel's.
            if shown != nil, !contentFrame.contains(NSEvent.mouseLocation) { hide() }
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap, settings.isEnabled { CGEvent.tapEnable(tap: tap, enable: true) }
        default:
            break
        }
    }

    // MARK: Pointer

    private func pointerMoved(_ point: NSPoint) {
        defer { drawArea() }
        // The user can move or resize the Dock at any moment.
        if Date().timeIntervalSince(layoutRead) > 2 {
            layout = DockLayout.current()
            layoutRead = Date()
        }

        if let shown {
            if contentFrame.insetBy(dx: -6, dy: -6).contains(point) || corridor(to: shown).contains(point) {
                cancelHide()
                cancelOpen()
                return
            }
            if layout.isNear(point), let item = DockItems.item(at: point) {
                cancelHide()
                if item.app.processIdentifier == shown.app.processIdentifier {
                    lastOnIcon = point
                    cancelOpen()
                } else {
                    // Sliding along the Dock: the next app follows quickly.
                    scheduleOpen(item, delay: min(settings.openDelay.seconds, 0.1))
                }
                return
            }
            cancelOpen()
            scheduleHide()
            return
        }

        // Accessibility is only asked near the Dock, not on every move across the screen.
        guard layout.isNear(point), let item = DockItems.item(at: point) else {
            clickedPID = nil
            cancelOpen()
            return
        }
        // Still on the icon just clicked; leaving it ends that.
        if item.app.processIdentifier == clickedPID { return }
        clickedPID = nil
        scheduleOpen(item, delay: settings.openDelay.seconds)
    }

    /// The way from the icon to the panel: a triangle from where the pointer last was on the
    /// icon to the panel's corners on the Dock's side. Heading for any window, even diagonally
    /// across other icons, stays inside it; sliding along the Dock leaves it at once, so the
    /// next app's preview still follows.
    private func corridor(to item: DockItem) -> Corridor {
        let tip = lastOnIcon ?? NSPoint(x: item.frame.midX, y: item.frame.midY)
        let panel = contentFrame
        switch layout.edge {
        case .bottom:
            return Corridor([tip, NSPoint(x: panel.maxX, y: panel.minY), NSPoint(x: panel.minX, y: panel.minY)])
        case .left:
            return Corridor([tip, NSPoint(x: panel.minX, y: panel.minY), NSPoint(x: panel.minX, y: panel.maxY)])
        case .right:
            return Corridor([tip, NSPoint(x: panel.maxX, y: panel.maxY), NSPoint(x: panel.maxX, y: panel.minY)])
        }
    }

    /// Shows the panel, the icon and the way between them, tinted, over everything and letting
    /// clicks through, while Developer > Settings asks for it.
    private func drawArea() {
        guard UserDefaults.standard.bool(forKey: Self.showsAreaKey), let shown,
              let screen = NSScreen.screens.first(where: { $0.frame.intersects(shown.frame) })
        else {
            areaPanel?.orderOut(nil)
            return
        }
        let panel = areaPanel ?? {
            let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
            panel.contentView = AreaView()
            return panel
        }()
        areaPanel = panel
        panel.setFrame(screen.frame, display: false)
        if let view = panel.contentView as? AreaView {
            let origin = screen.frame.origin
            let local = { (point: NSPoint) in NSPoint(x: point.x - origin.x, y: point.y - origin.y) }
            view.corridor = corridor(to: shown).corners.map(local)
            view.rects = [contentFrame.insetBy(dx: -6, dy: -6), shown.frame].map { $0.offsetBy(dx: -origin.x, dy: -origin.y) }
            view.needsDisplay = true
        }
        panel.orderFrontRegardless()
    }

    private func scheduleOpen(_ item: DockItem, delay: TimeInterval) {
        if pendingOpen?.pid == item.app.processIdentifier { return }
        cancelOpen()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pendingOpen = nil
                // Still on that icon.
                guard let current = DockItems.item(at: NSEvent.mouseLocation),
                      current.app.processIdentifier == item.app.processIdentifier,
                      current.app.processIdentifier != self.clickedPID,
                      // Not over the Dock's own menu (right click, or a long press).
                      !DockItems.isMenuOpen()
                else { return }
                self.show(current)
            }
        }
        pendingOpen = (item.app.processIdentifier, work)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelOpen() {
        pendingOpen?.work.cancel()
        pendingOpen = nil
    }

    private func scheduleHide() {
        guard pendingHide == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pendingHide = nil
                guard let shown = self.shown else { return }
                let point = NSEvent.mouseLocation
                let onOwnIcon = self.layout.isNear(point)
                    && DockItems.item(at: point)?.app.processIdentifier == shown.app.processIdentifier
                if self.contentFrame.insetBy(dx: -6, dy: -6).contains(point) || self.corridor(to: shown).contains(point) || onOwnIcon {
                    return
                }
                self.hide()
            }
        }
        pendingHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hideDelay, execute: work)
    }

    private func cancelHide() {
        pendingHide?.cancel()
        pendingHide = nil
    }

    // MARK: Panel

    private func show(_ item: DockItem) {
        guard #available(macOS 14, *) else { return }
        let windows = AppWindows.windows(of: item.app.processIdentifier, currentDesktopOnly: settings.currentDesktopOnly)
        guard !windows.isEmpty else {
            hide()
            return
        }
        cancelHide()
        captureTask?.cancel()

        // Taken away since: no window contents at all, not even remembered ones.
        if !CGPreflightScreenCaptureAccess() { thumbnailCache = [:] }
        shown = item
        lastOnIcon = NSEvent.mouseLocation
        state.app = item.app
        state.windows = windows
        state.thumbnails = thumbnailCache.filter { id, _ in windows.contains { $0.id == id } }
        state.closable = Set(windows.filter { AppWindows.canClose($0, of: item.app.processIdentifier) }.map(\.id))
        state.isHorizontal = layout.edge == .bottom

        let panel = panel ?? makePanel()
        self.panel = panel
        if let view = panel.contentView {
            let fitting = view.fittingSize
            place(CGSize(width: fitting.width - 2 * Self.shadowRoom, height: fitting.height - 2 * Self.shadowRoom))
        }
        panel.orderFrontRegardless()
        state.selected = nil
        scrolled = 0
        setInputTap(enabled: true)
        // An automatically hidden Dock stays while the pointer is on the panel.
        DockHold.begin()

        // Sharp on Retina: twice the points, and room for the widest shape.
        let maxPixels = CGFloat(settings.size) * 2 * 2
        captureTask = AppWindows.captureThumbnails(of: windows, maxPixels: maxPixels) { [weak self] id, image in
            self?.thumbnailCache[id] = image
            guard self?.state.windows.contains(where: { $0.id == id }) == true else { return }
            self?.state.thumbnails[id] = image
        }
    }

    private func hide() {
        cancelOpen()
        cancelHide()
        captureTask?.cancel()
        captureTask = nil
        shown = nil
        lastOnIcon = nil
        areaPanel?.orderOut(nil)
        contentFrame = .zero
        panel?.orderOut(nil)
        state.windows = []
        state.app = nil
        state.selected = nil
        pendingFocus?.cancel()
        pendingFocus = nil
        keepThroughDesktopChangesUntil = .distantPast
        setInputTap(enabled: false)
        DockHold.end()
    }

    private func setInputTap(enabled: Bool) {
        if inputTap == nil, enabled {
            let types: [CGEventType] = [.scrollWheel, .keyDown]
            inputTap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: types.reduce(CGEventMask(0)) { $0 | 1 << $1.rawValue },
                callback: dockPreviewInputCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
            guard let inputTap else { return }
            CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, inputTap, 0), .commonModes)
        }
        if let inputTap { CGEvent.tapEnable(tap: inputTap, enable: enabled) }
    }

    /// Returns true to keep the event from reaching the app underneath.
    fileprivate func handleInput(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let inputTap, shown != nil { CGEvent.tapEnable(tap: inputTap, enable: true) }
            return false
        }
        guard shown != nil, !state.windows.isEmpty else { return false }
        switch type {
        case .scrollWheel:
            // Off: the scroll goes on to the app underneath.
            guard settings.scrollSwitchesWindows else { return false }
            let isTrackpad = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
            let vertical = event.getDoubleValueField(isTrackpad ? .scrollWheelEventPointDeltaAxis1 : .scrollWheelEventDeltaAxis1)
            let horizontal = event.getDoubleValueField(isTrackpad ? .scrollWheelEventPointDeltaAxis2 : .scrollWheelEventDeltaAxis2)
            let delta = CGFloat(abs(vertical) >= abs(horizontal) ? vertical : horizontal)
            if isTrackpad {
                scrolled += delta
                guard abs(scrolled) >= 30 else { return true }
                moveSelection(by: scrolled < 0 ? 1 : -1)
                scrolled = 0
            } else if delta != 0 {
                // One notch, one window; down or right moves on.
                moveSelection(by: delta < 0 ? 1 : -1)
            }
            return true
        case .keyDown:
            switch event.getIntegerValueField(.keyboardEventKeycode) {
            case 36, 76: // Return, Enter
                guard let selected = state.selected, let window = state.windows.first(where: { $0.id == selected }) else { return false }
                open(window)
                return true
            case 53: // Esc
                hide()
                return true
            default:
                return false
            }
        default:
            return false
        }
    }

    private func moveSelection(by step: Int) {
        let windows = state.windows
        guard !windows.isEmpty else { return }
        let index = state.selected.flatMap { id in windows.firstIndex { $0.id == id } }
        let next = index.map { ($0 + step + windows.count) % windows.count } ?? (step > 0 ? 0 : windows.count - 1)
        state.selected = windows[next].id
        focusSelected()
    }

    /// Each step brings the highlighted window forward, going to its desktop if needed, with
    /// the panel still open to keep scrolling; a fast spin only acts on where it stops.
    private func focusSelected() {
        pendingFocus?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard #available(macOS 14, *), let self, let app = self.state.app,
                      let window = self.state.windows.first(where: { $0.id == self.state.selected })
                else { return }
                // Long enough for a trip across several desktops.
                self.keepThroughDesktopChangesUntil = Date().addingTimeInterval(4)
                AppWindows.open(window, of: app)
            }
        }
        pendingFocus = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Above the Dock.
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        let view = DockPreviewView(
            state: state,
            settings: settings,
            open: { [weak self] window in self?.open(window) },
            close: { [weak self] window in self?.close(window) }
        )
        panel.contentView = OverlayHostingView(rootView: view
            .background(SizeReader { [weak self] size in self?.place(size) })
            .padding(Self.shadowRoom)
            .environmentObject(AppearanceSettings(usesDefaults: true)))
        return panel
    }

    /// The content is `size`; it sits next to the icon, centred on it, kept on its screen.
    private func place(_ size: CGSize) {
        guard let panel, let shown, size.width > 0, size.height > 0 else { return }
        let icon = shown.frame
        let screen = NSScreen.screens.first { $0.frame.intersects(icon) }?.frame ?? NSScreen.main?.frame ?? .zero
        var content: NSRect
        switch layout.edge {
        case .bottom:
            content = NSRect(x: icon.midX - size.width / 2, y: icon.maxY + Self.gap, width: size.width, height: size.height)
        case .left:
            content = NSRect(x: icon.maxX + Self.gap, y: icon.midY - size.height / 2, width: size.width, height: size.height)
        case .right:
            content = NSRect(x: icon.minX - Self.gap - size.width, y: icon.midY - size.height / 2, width: size.width, height: size.height)
        }
        content.origin.x = min(max(content.minX, screen.minX + 8), screen.maxX - 8 - content.width)
        content.origin.y = min(max(content.minY, screen.minY + 8), screen.maxY - 8 - content.height)
        contentFrame = content
        panel.setFrame(content.insetBy(dx: -Self.shadowRoom, dy: -Self.shadowRoom), display: true)
    }

    // MARK: Windows

    private func open(_ window: AppWindow) {
        guard #available(macOS 14, *), let app = state.app else { return }
        hide()
        AppWindows.open(window, of: app)
    }

    private func close(_ window: AppWindow) {
        guard #available(macOS 14, *), let app = state.app else { return }
        AppWindows.close(window, of: app)
        state.windows.removeAll { $0.id == window.id }
        thumbnailCache[window.id] = nil
        if state.windows.isEmpty { hide() }
    }

    private func log(_ message: String) {
        appLog.record(message, source: "Dock Preview")
    }
}

/// Plain C function for the event tap; the utility comes back through the refcon. Runs on the
/// main run loop, where the tap is scheduled.
private func dockPreviewCallback(
    _ proxy: CGEventTapProxy,
    _ type: CGEventType,
    _ event: CGEvent,
    _ refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if let refcon {
        let utility = Unmanaged<DockPreview>.fromOpaque(refcon).takeUnretainedValue()
        MainActor.assumeIsolated { utility.handle(type) }
    }
    return Unmanaged.passUnretained(event)
}

/// The input tap's callback: a nil return keeps the event from the app underneath.
private func dockPreviewInputCallback(
    _ proxy: CGEventTapProxy,
    _ type: CGEventType,
    _ event: CGEvent,
    _ refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let utility = Unmanaged<DockPreview>.fromOpaque(refcon).takeUnretainedValue()
    let swallowed = MainActor.assumeIsolated { utility.handleInput(type, event) }
    return swallowed ? nil : Unmanaged.passUnretained(event)
}

/// A convex area given by its corners in order.
private struct Corridor {
    let corners: [NSPoint]

    init(_ corners: [NSPoint]) {
        self.corners = corners
    }

    /// On the same side of every edge (or on one).
    func contains(_ point: NSPoint) -> Bool {
        var sign: CGFloat = 0
        for index in corners.indices {
            let a = corners[index]
            let b = corners[(index + 1) % corners.count]
            let cross = (b.x - a.x) * (point.y - a.y) - (b.y - a.y) * (point.x - a.x)
            if cross == 0 { continue }
            if sign == 0 {
                sign = cross
            } else if (cross > 0) != (sign > 0) {
                return false
            }
        }
        return true
    }
}

/// Draws the area that keeps the panel open: the panel and the icon in blue, the way between
/// them in orange.
private final class AreaView: NSView {
    var corridor: [NSPoint] = []
    var rects: [NSRect] = []

    override func draw(_ dirtyRect: NSRect) {
        for rect in rects {
            NSColor.systemBlue.withAlphaComponent(0.15).setFill()
            rect.fill()
            NSColor.systemBlue.setStroke()
            NSBezierPath(rect: rect).stroke()
        }
        guard let first = corridor.first else { return }
        let path = NSBezierPath()
        path.move(to: first)
        corridor.dropFirst().forEach(path.line(to:))
        path.close()
        NSColor.systemOrange.withAlphaComponent(0.25).setFill()
        path.fill()
        NSColor.systemOrange.setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }
}
