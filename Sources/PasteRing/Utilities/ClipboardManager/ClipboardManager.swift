import AppKit
import Combine
import SwiftUI

/// The clipboard utility: records copied text and shows the overlay on its shortcuts.
/// Owns everything it needs, so the app only has to create it and call `start()`.
@MainActor
final class ClipboardManager: NSObject {
    let history = ClipboardHistory()
    let settings = ClipboardSettings()
    let appearance = AppearanceSettings()

    private let monitor: ClipboardMonitor
    private let overlay: OverlayController
    private var observers: Set<AnyCancellable> = []
    private var hotKeys: [UInt32] = []

    init(general: GeneralSettings) {
        monitor = ClipboardMonitor(history: history, settings: settings)
        overlay = OverlayController(history: history, monitor: monitor, settings: settings, appearance: appearance, general: general)
        super.init()
    }

    func start() {
        settings.$maxItems
            .sink { [weak self] in self?.history.limit = $0 }
            .store(in: &observers)
        // Re-register whenever the shortcuts change in Settings.
        settings.$shortcuts
            .sink { [weak self] in self?.registerShortcuts($0) }
            .store(in: &observers)
        monitor.start()
    }

    private func registerShortcuts(_ shortcuts: [Shortcut]) {
        hotKeys.forEach(HotKeyCenter.shared.unregister)
        hotKeys = shortcuts.map { shortcut in
            HotKeyCenter.shared.register(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers) { [weak self] in
                self?.overlay.cycle(with: shortcut)
            }
        }
    }

    /// Entries for the menu bar menu.
    func menuItems() -> [NSMenuItem] {
        let clear = NSMenuItem(title: "Clear Clipboard History", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        return [clear]
    }

    /// The pane shown for this utility in Settings.
    func settingsPane() -> some View {
        ClipboardManagerPane(clipboard: settings, appearance: appearance, history: history)
    }

    @objc private func clearHistory() {
        history.clear()
    }
}
