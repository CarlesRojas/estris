import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class OverlayState: ObservableObject {
    @Published var items: [ClipItem] = []
    /// Steps taken since opening. Unbounded so the ring keeps turning the same way when it wraps.
    @Published var position = 0
    /// Grid tiles fitted to the screen the overlay opened on.
    @Published var gridLayout: GridLayout?

    var actions = OverlayActions()

    var selected: Int {
        items.isEmpty ? 0 : (position % items.count + items.count) % items.count
    }

    var selectedItem: ClipItem? {
        items.indices.contains(selected) ? items[selected] : nil
    }

    struct Slot: Identifiable {
        let id: String
        let item: ClipItem
        let distance: Int
    }

    /// Places each entry at its circular distance from the selection, for styles that loop.
    /// `lap` is part of the identity, so an entry that wraps to the other end leaves and
    /// re-enters (with its transition) instead of sweeping across the selection.
    func circularSlots(within range: ClosedRange<Int>) -> [Slot] {
        let count = items.count
        guard count > 0 else { return [] }
        let lowest = -(count - 1) / 2
        return items.enumerated().compactMap { index, item in
            let raw = index - position
            let shifted = raw - lowest
            let lap = shifted >= 0 ? shifted / count : -((-shifted + count - 1) / count)
            let distance = raw - lap * count
            guard range.contains(distance) else { return nil }
            return Slot(id: "\(item.id)-\(lap)", item: item, distance: distance)
        }
    }
}

/// Shows the overlay while ⌘⇧ is held. ⌘⇧V, ⌘⇧ arrows and the scroll wheel move the
/// selection, releasing pastes the selected entry, ⌘⇧Esc cancels, ⌘⇧Delete removes the
/// selected entry. While ⌘⇧ is held, clicking an entry pastes it.
@MainActor
final class OverlayController: NSObject {
    private static let fadeDuration: TimeInterval = 0.15

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
    private var lastScrollStep: Date = .distantPast
    /// Fastest the scroll wheel may cycle: one entry per this many seconds.
    private static let scrollStepInterval: TimeInterval = 0.09
    private var isVisible = false
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
        let screen = screenWithMouse()
        var visibleLimit = settings.visibleLimit ?? history.items.count
        var gridLayout: GridLayout?
        if settings.style == .grid, let size = screen?.visibleFrame.size {
            let layout = GridLayout.fitting(settings, in: size)
            visibleLimit = min(visibleLimit, layout.rows * GridLayout.columns)
            gridLayout = layout
        }
        // Reset without animating, so the overlay opens already on the first entry.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            state.items = Array(history.items.prefix(visibleLimit))
            state.position = 0
            state.gridLayout = gridLayout
        }
        scrollAccumulator = 0
        lastScrollStep = .distantPast
        isVisible = true
        presentation += 1

        if !panel.isVisible {
            panel.alphaValue = 0
            panel.present(on: screen)
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

        // Capped at one step's worth, so a fast flick does not queue up extra steps.
        scrollAccumulator = max(-threshold, min(threshold, scrollAccumulator + delta))
        guard abs(scrollAccumulator) >= threshold,
              Date().timeIntervalSince(lastScrollStep) >= Self.scrollStepInterval
        else { return }

        // Content follows the gesture, so scrolling "up" brings the next entry up.
        move(by: scrollAccumulator < 0 ? 1 : -1)
        scrollAccumulator = 0
        lastScrollStep = Date()
    }

    @objc private func tick() {
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
