import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Shows the overlay while the shortcut's modifiers are held (⌘⇧ for the default ⌘⇧V).
/// Pressing the shortcut again, the arrows (with those modifiers) or scrolling moves the
/// selection; releasing pastes the selected entry; Esc cancels; Delete removes the
/// selected entry. While the modifiers are held, clicking an entry pastes it.
@MainActor
final class OverlayController: NSObject {
    private static let fadeDuration: TimeInterval = 0.15

    private let history: ClipboardHistory
    private let monitor: ClipboardMonitor
    private let settings: ClipboardSettings
    private let appearance: AppearanceSettings
    private let general: GeneralSettings
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
    private var activeShortcut: Shortcut { state.activeShortcut }
    /// Bumped on every show and hide, so a finished fade-out does not hide a newer show.
    private var presentation = 0

    init(history: ClipboardHistory, monitor: ClipboardMonitor, settings: ClipboardSettings, appearance: AppearanceSettings, general: GeneralSettings) {
        self.history = history
        self.monitor = monitor
        self.settings = settings
        self.appearance = appearance
        self.general = general
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
        let hostingView = OverlayHostingView(rootView: OverlayRootView(state: state, settings: settings, appearance: appearance, general: general))
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        panel.onScroll = { [weak self] event in
            self?.handleScroll(event)
        }
    }

    /// Opens the overlay, or moves to the next entry if it is already open. `shortcut` is
    /// the one that was pressed: the overlay stays open while its modifiers are held.
    func cycle(with shortcut: Shortcut) {
        if isVisible {
            move(by: 1)
        } else {
            state.activeShortcut = shortcut
            show()
        }
    }

    /// Closes the overlay without pasting.
    func dismiss() {
        hide()
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

        registerKeys(modifiers: activeShortcut.modifiers)
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
        ] + Self.digitKeys.enumerated().map { index, keyCode -> (Int, () -> Void) in
            (keyCode, { [weak self] in self?.quickPick(index) })
        }
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

    private static let digitKeys = [
        kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
        kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9,
    ]

    /// Pastes the entry at `index` (0 for the key 1).
    private func quickPick(_ index: Int) {
        guard state.items.indices.contains(index) else { return }
        commit(state.items[index])
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
        // Releasing any of the shortcut's modifiers pastes.
        if !NSEvent.modifierFlags.isSuperset(of: activeShortcut.modifierFlags) {
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
        if settings.moveToTopOnPaste {
            history.promote(item)
        }
        monitor.write(item)

        guard Paster.isTrusted(prompt: true) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            Paster.paste()
        }

        // Without moving to the top, put the last copied text back once the paste has gone
        // through, so the next ⌘V pastes what was copied last, not what was picked.
        if !settings.moveToTopOnPaste, let latest = history.items.first, latest.id != item.id {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 400_000_000)
                self?.monitor.write(latest)
            }
        }
    }

    private func screenWithMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }
}
