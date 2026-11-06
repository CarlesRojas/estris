import AppKit

/// One color pick: a see-through window over each screen catches the pointer, a click and
/// Esc, while the HUD follows the pointer with the loupe and the value under it. Picks on
/// release. Ends itself by calling `done` with the color, or nil when cancelled.
@MainActor
final class PickerSession {
    /// Points around the pointer shown in the loupe.
    private static let loupeArea: CGFloat = 15

    private let hud: PickerHUD
    private let format: (NSColor) -> String
    private let done: (NSColor?, NSPoint) -> Void
    private var windows: [PickerWindow] = []
    private var color: NSColor?

    init(hud: PickerHUD, format: @escaping (NSColor) -> String, done: @escaping (NSColor?, NSPoint) -> Void) {
        self.hud = hud
        self.format = format
        self.done = done
    }

    func begin() {
        windows = NSScreen.screens.map { screen in
            let window = PickerWindow(screen: screen)
            window.onMove = { [weak self] in self?.update() }
            window.onPick = { [weak self] in self?.finish(cancelled: false) }
            window.onCancel = { [weak self] in self?.finish(cancelled: true) }
            window.orderFrontRegardless()
            return window
        }
        NSApp.activate(ignoringOtherApps: true)
        windows.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }?.makeKey()
        NSCursor.crosshair.push()
        update()
    }

    private func update() {
        let point = NSEvent.mouseLocation
        guard let window = windows.first(where: { NSMouseInRect(point, $0.frame, false) }) ?? windows.first,
              let image = ScreenSampler.capture(around: point, size: Self.loupeArea, below: window.windowNumber)
        else { return }
        let color = ScreenSampler.centerColor(of: image)
        self.color = color
        hud.model.loupe = image
        hud.model.isCopied = false
        if let color {
            hud.model.color = color
            hud.model.text = format(color)
        }
        hud.move(to: point)
    }

    private func finish(cancelled: Bool) {
        update()
        NSCursor.pop()
        windows.forEach { $0.orderOut(nil) }
        windows = []
        done(cancelled ? nil : color, NSEvent.mouseLocation)
    }
}

/// A nearly clear window over one screen that takes the pointer while picking.
private final class PickerWindow: NSWindow {
    var onMove: () -> Void = {}
    var onPick: () -> Void = {}
    var onCancel: () -> Void = {}

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        // Fully clear windows let clicks through; this one has to catch them.
        backgroundColor = NSColor(white: 0, alpha: 0.001)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = false
        let view = PickerView()
        view.window_ = self
        contentView = view
        setFrame(screen.frame, display: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var canBecomeKey: Bool { true }
}

private final class PickerView: NSView {
    weak var window_: PickerWindow?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect, .cursorUpdate], owner: self, userInfo: nil))
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }
    override func mouseMoved(with event: NSEvent) { window_?.onMove() }
    override func mouseDragged(with event: NSEvent) { window_?.onMove() }
    override func mouseUp(with event: NSEvent) { window_?.onPick() }
    override func rightMouseUp(with event: NSEvent) { window_?.onCancel() }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { window_?.onCancel() } else { super.keyDown(with: event) }
    }
}
