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
    /// How long the pointer may be away from the icon and the panel before it closes.
    private static let hideDelay: TimeInterval = 0.3

    let settings = DockPreviewSettings()
    private let state = DockPreviewState()
    private let appLog: AppLog
    private var observers: Set<AnyCancellable> = []
    private var tap: CFMachPort?
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
    /// The last thumbnail of each window, shown at once the next time.
    private var thumbnailCache: [CGWindowID: CGImage] = [:]

    init(log: AppLog) {
        appLog = log
    }

    func start() {
        guard Self.isSupported else { return }
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
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    fileprivate func handle(_ type: CGEventType) {
        switch type {
        case .mouseMoved:
            pointerMoved(NSEvent.mouseLocation)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            cancelOpen()
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
            cancelOpen()
            return
        }
        scheduleOpen(item, delay: settings.openDelay.seconds)
    }

    /// The space between the icon and the panel, crossed on the way up to it.
    private func corridor(to item: DockItem) -> NSRect {
        let icon = item.frame
        switch layout.edge {
        case .bottom:
            return NSRect(x: icon.minX, y: icon.midY, width: icon.width, height: max(0, contentFrame.minY - icon.midY))
        case .left:
            return NSRect(x: icon.midX, y: icon.minY, width: max(0, contentFrame.minX - icon.midX), height: icon.height)
        case .right:
            return NSRect(x: contentFrame.maxX, y: icon.minY, width: max(0, icon.midX - contentFrame.maxX), height: icon.height)
        }
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
                      current.app.processIdentifier == item.app.processIdentifier
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

        shown = item
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
        contentFrame = .zero
        panel?.orderOut(nil)
        state.windows = []
        state.app = nil
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
