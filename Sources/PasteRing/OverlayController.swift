import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class OverlayState: ObservableObject {
    @Published var items: [ClipItem] = []
    @Published var selected = 0
}

/// Shows the ring while ⌘⇧ is held. Each ⌘⇧V advances, releasing pastes, ⌘⇧Esc cancels.
@MainActor
final class OverlayController: NSObject {
    private let history: ClipboardHistory
    private let monitor: ClipboardMonitor
    private let state = OverlayState()
    private let panel: OverlayPanel
    private var modifierTimer: Timer?
    private var cancelHotKey: UInt32?

    init(history: ClipboardHistory, monitor: ClipboardMonitor) {
        self.history = history
        self.monitor = monitor
        panel = OverlayPanel(
            contentRect: NSRect(origin: .zero, size: RingView.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        panel.configure()
        panel.contentView = NSHostingView(rootView: RingView(state: state))
    }

    func cycle() {
        if panel.isVisible {
            guard !state.items.isEmpty else { return }
            state.selected = (state.selected + 1) % state.items.count
        } else {
            show()
        }
    }

    private func show() {
        state.items = history.items
        state.selected = 0
        panel.present(on: screenWithMouse())

        let timer = Timer(timeInterval: 1.0 / 60.0, target: self, selector: #selector(checkModifiers), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        modifierTimer = timer

        cancelHotKey = HotKeyCenter.shared.register(
            keyCode: UInt32(kVK_Escape),
            modifiers: UInt32(cmdKey | shiftKey)
        ) { [weak self] in
            self?.hide()
        }
    }

    private func hide() {
        modifierTimer?.invalidate()
        modifierTimer = nil
        if let cancelHotKey {
            HotKeyCenter.shared.unregister(cancelHotKey)
            self.cancelHotKey = nil
        }
        panel.orderOut(nil)
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

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func configure() {
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    func present(on screen: NSScreen?) {
        if let visible = screen?.visibleFrame {
            setFrameOrigin(NSPoint(x: visible.midX - frame.width / 2, y: visible.midY - frame.height / 2))
        }
        orderFrontRegardless()
    }
}
