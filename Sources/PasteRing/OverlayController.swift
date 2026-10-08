import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class OverlayState: ObservableObject {
    @Published var items: [ClipItem] = []
    /// Steps taken since opening. Unbounded so the ring keeps turning the same way when it wraps.
    @Published var position = 0

    var selected: Int {
        items.isEmpty ? 0 : (position % items.count + items.count) % items.count
    }
}

/// Shows the overlay while ⌘⇧ is held. ⌘⇧V, ⌘⇧ arrows and the scroll wheel move the
/// selection, releasing pastes, ⌘⇧Esc cancels.
@MainActor
final class OverlayController: NSObject {
    private let history: ClipboardHistory
    private let monitor: ClipboardMonitor
    private let settings: AppSettings
    private let state = OverlayState()
    private let panel: OverlayPanel
    private var modifierTimer: Timer?
    /// Hotkeys that only exist while the overlay is visible.
    private var sessionHotKeys: [UInt32] = []
    private var scrollAccumulator: CGFloat = 0

    init(history: ClipboardHistory, monitor: ClipboardMonitor, settings: AppSettings) {
        self.history = history
        self.monitor = monitor
        self.settings = settings
        panel = OverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 600),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        panel.configure()
        let hostingView = NSHostingView(rootView: OverlayRootView(state: state, settings: settings))
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        panel.onScroll = { [weak self] event in
            self?.handleScroll(event)
        }
    }

    func cycle() {
        if panel.isVisible {
            move(by: 1)
        } else {
            show()
        }
    }

    private func move(by step: Int) {
        let count = state.items.count
        guard count > 0 else { return }
        state.position += step
    }

    private func show() {
        state.items = history.items
        state.position = 0
        scrollAccumulator = 0
        panel.present(on: screenWithMouse())

        let timer = Timer(timeInterval: 1.0 / 60.0, target: self, selector: #selector(checkModifiers), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        modifierTimer = timer

        let bindings: [(Int, () -> Void)] = [
            (kVK_Escape, { [weak self] in self?.hide() }),
            (kVK_UpArrow, { [weak self] in self?.move(by: -1) }),
            (kVK_LeftArrow, { [weak self] in self?.move(by: -1) }),
            (kVK_DownArrow, { [weak self] in self?.move(by: 1) }),
            (kVK_RightArrow, { [weak self] in self?.move(by: 1) }),
        ]
        sessionHotKeys = bindings.map { keyCode, handler in
            HotKeyCenter.shared.register(keyCode: UInt32(keyCode), modifiers: UInt32(cmdKey | shiftKey), handler: handler)
        }
    }

    private func hide() {
        modifierTimer?.invalidate()
        modifierTimer = nil
        sessionHotKeys.forEach(HotKeyCenter.shared.unregister)
        sessionHotKeys = []
        panel.orderOut(nil)
    }

    /// Trackpads send many small precise deltas, mouse wheels send whole lines.
    /// Shift turns a mouse wheel into horizontal scrolling, so both axes count.
    private func handleScroll(_ event: NSEvent) {
        guard event.momentumPhase.isEmpty else { return }
        let delta = abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) ? event.scrollingDeltaY : event.scrollingDeltaX
        let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 30 : 1

        scrollAccumulator += delta
        while abs(scrollAccumulator) >= threshold {
            // Content follows the gesture, so scrolling "up" brings the next entry up.
            move(by: scrollAccumulator < 0 ? 1 : -1)
            scrollAccumulator -= scrollAccumulator < 0 ? -threshold : threshold
        }
    }

    @objc private func checkModifiers() {
        let flags = NSEvent.modifierFlags
        if !flags.contains(.command) || !flags.contains(.shift) {
            commit()
        }
    }

    private func commit() {
        hide()
        guard state.items.indices.contains(state.selected) else { return }
        let item = state.items[state.selected]
        history.promote(item)
        monitor.write(item.text)

        guard Paster.isTrusted(prompt: true) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            Paster.paste()
        }
    }

    private func screenWithMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }
}

/// Transparent panel covering the whole screen so it receives scroll events wherever
/// the pointer is, keeping them from scrolling the app underneath.
final class OverlayPanel: NSPanel {
    var onScroll: ((NSEvent) -> Void)?

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func configure() {
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        ignoresMouseEvents = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    func present(on screen: NSScreen?) {
        if let screen {
            setFrame(screen.frame, display: true)
        }
        orderFrontRegardless()
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .scrollWheel {
            onScroll?(event)
        } else {
            super.sendEvent(event)
        }
    }
}
