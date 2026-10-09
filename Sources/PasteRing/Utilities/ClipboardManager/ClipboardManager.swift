import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

/// The clipboard utility: records copied text and shows the overlay on ⌘⇧V.
/// Owns everything it needs, so the app only has to create it and call `start()`.
@MainActor
final class ClipboardManager: NSObject {
    let history = ClipboardHistory()
    let settings = ClipboardSettings()
    let appearance = AppearanceSettings()

    private let monitor: ClipboardMonitor
    private let overlay: OverlayController
    private var maxItemsObserver: AnyCancellable?

    init(general: GeneralSettings) {
        monitor = ClipboardMonitor(history: history)
        overlay = OverlayController(history: history, monitor: monitor, settings: settings, appearance: appearance, general: general)
        super.init()
    }

    func start() {
        maxItemsObserver = settings.$maxItems.sink { [weak self] in
            self?.history.limit = $0
        }
        monitor.start()
        HotKeyCenter.shared.register(
            keyCode: UInt32(kVK_ANSI_V),
            modifiers: UInt32(cmdKey | shiftKey)
        ) { [weak self] in
            self?.overlay.cycle()
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
