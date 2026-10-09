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

    var selectedItem: ClipItem? {
        items.indices.contains(selected) ? items[selected] : nil
    }

    var actions = OverlayActions()
}

/// Shows the overlay while ⌘⇧ is held. ⌘⇧V, ⌘⇧ arrows and the scroll wheel move the
/// selection, releasing pastes, ⌘⇧Esc cancels, ⌘⇧Delete removes the selected entry.
///
/// Moving the mouse makes the overlay stay open after ⌘⇧ is released, so entries can be
/// clicked. It then also takes plain Return, Esc, arrows and Delete until it closes.
@MainActor
final class OverlayController: NSObject {
    private static let fadeDuration: TimeInterval = 0.15
    /// How far the pointer has to move before the overlay stops closing on release.
    private static let stickyDistance: CGFloat = 24

    private let history: ClipboardHistory
    private let monitor: ClipboardMonitor
    private let settings: AppSettings
    private let appearance: AppearanceSettings
    private let state = OverlayState()
    private let panel: OverlayPanel
    private var modifierTimer: Timer?
    /// Hotkeys that only exist while the overlay is visible.
    private var sessionHotKeys: [UInt32] = []
    private var scrollAccumulator: CGFloat = 0
    private var isVisible = false
    private var isSticky = false
    private var mouseAtShow: NSPoint = .zero
    /// Bumped on every show and hide, so a finished fade-out does not hide a newer show.
    private var presentation = 0

    init(history: ClipboardHistory, monitor: ClipboardMonitor, settings: AppSettings, appearance: AppearanceSettings) {
        self.history = history
        self.monitor = monitor
        self.settings = settings
        self.appearance = appearance
        panel = OverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 600),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        panel.configure()
        state.actions = OverlayActions(
            pick: { [weak self] item in self?.commit(item) },
            delete: { [weak self] item in self?.delete(item) },
            dismiss: { [weak self] in self?.hide() },
            isEnabled: true
        )
        let hostingView = OverlayHostingView(rootView: OverlayRootView(state: state, settings: settings, appearance: appearance))
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        panel.onScroll = { [weak self] event in
            self?.handleScroll(event)
        }
    }

    func cycle() {
        if isVisible {
            move(by: 1)
        } else {
            show()
        }
    }

    private func move(by step: Int) {
        guard !state.items.isEmpty else { return }
        state.position += step
    }

    private func show() {
        let visibleLimit = settings.visibleLimit ?? history.items.count
        // Reset without animating, so the overlay opens already on the first entry.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            state.items = Array(history.items.prefix(visibleLimit))
            state.position = 0
        }
        scrollAccumulator = 0
        isVisible = true
        isSticky = false
        mouseAtShow = NSEvent.mouseLocation
        presentation += 1

        if !panel.isVisible {
            panel.alphaValue = 0
            panel.present(on: screenWithMouse())
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeDuration
            panel.animator().alphaValue = 1
        }

        let timer = Timer(timeInterval: 1.0 / 60.0, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        modifierTimer = timer

        registerKeys(modifiers: UInt32(cmdKey | shiftKey))
    }

    private func registerKeys(modifiers: UInt32) {
        let bindings: [(Int, () -> Void)] = [
            (kVK_Escape, { [weak self] in self?.hide() }),
            (kVK_UpArrow, { [weak self] in self?.move(by: -1) }),
            (kVK_LeftArrow, { [weak self] in self?.move(by: -1) }),
            (kVK_DownArrow, { [weak self] in self?.move(by: 1) }),
            (kVK_RightArrow, { [weak self] in self?.move(by: 1) }),
            (kVK_Delete, { [weak self] in self?.deleteSelected() }),
            (kVK_ForwardDelete, { [weak self] in self?.deleteSelected() }),
        ]
        sessionHotKeys += bindings.map { keyCode, handler in
            HotKeyCenter.shared.register(keyCode: UInt32(keyCode), modifiers: modifiers, handler: handler)
        }
    }

    private func hide() {
        guard isVisible else { return }
        isVisible = false
        modifierTimer?.invalidate()
        modifierTimer = nil
        sessionHotKeys.forEach(HotKeyCenter.shared.unregister)
        sessionHotKeys = []

        presentation += 1
        let fadingOut = presentation
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeDuration
            panel.animator().alphaValue = 0
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.fadeDuration * 1_000_000_000))
            guard let self, self.presentation == fadingOut else { return }
            self.panel.orderOut(nil)
        }
    }

    /// Stops closing on release once the pointer moves, and takes plain keys instead.
    private func becomeSticky() {
        isSticky = true
        registerKeys(modifiers: 0)
        let confirm: [Int] = [kVK_Return, kVK_ANSI_KeypadEnter]
        sessionHotKeys += confirm.map { keyCode in
            HotKeyCenter.shared.register(keyCode: UInt32(keyCode), modifiers: 0) { [weak self] in
                self?.commit()
            }
        }
    }

    private func deleteSelected() {
        guard let item = state.selectedItem else { return }
        delete(item)
    }

    private func delete(_ item: ClipItem) {
        guard let index = state.items.firstIndex(of: item) else { return }
        let selected = state.selected
        history.remove(item)
        state.items.remove(at: index)
        guard !state.items.isEmpty else {
            state.position = 0
            return
        }
        // Keep the same entry selected, or the one that took the deleted entry's place.
        state.position = index < selected ? selected - 1 : min(selected, state.items.count - 1)
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

    @objc private func tick() {
        if !isSticky {
            let mouse = NSEvent.mouseLocation
            if hypot(mouse.x - mouseAtShow.x, mouse.y - mouseAtShow.y) > Self.stickyDistance {
                becomeSticky()
            }
        }
        guard !isSticky else { return }
        let flags = NSEvent.modifierFlags
        if !flags.contains(.command) || !flags.contains(.shift) {
            commit()
        }
    }

    /// Pastes `item`, or the selected entry when nil.
    private func commit(_ item: ClipItem? = nil) {
        guard let item = item ?? state.selectedItem else {
            hide()
            return
        }
        hide()
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

/// Lets the first click on an overlay element act right away; the panel never becomes key.
final class OverlayHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
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
