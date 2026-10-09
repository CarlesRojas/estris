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
    private var hasStarted = false
    private var expiryTimer: Timer?

    init(general: GeneralSettings) {
        monitor = ClipboardMonitor(history: history, settings: settings)
        overlay = OverlayController(history: history, monitor: monitor, settings: settings, appearance: appearance, general: general)
        super.init()
    }

    func start() {
        settings.$maxItems
            .sink { [weak self] in self?.history.limit = $0 }
            .store(in: &observers)
        // Published values arrive before the property changes, so use the value passed in.
        settings.$isEnabled
            .removeDuplicates()
            .sink { [weak self] in self?.setActive($0) }
            .store(in: &observers)
        settings.$expiry
            .sink { [weak self] in self?.removeExpired($0) }
            .store(in: &observers)
        let expiryTimer = Timer(timeInterval: 60, target: self, selector: #selector(checkExpiry), userInfo: nil, repeats: true)
        RunLoop.main.add(expiryTimer, forMode: .common)
        self.expiryTimer = expiryTimer
        // Re-register whenever the shortcuts change in Settings.
        settings.$shortcuts
            .sink { [weak self] shortcuts in
                guard let self, self.settings.isEnabled else { return }
                self.registerShortcuts(shortcuts)
            }
            .store(in: &observers)
    }

    /// Turning the utility off stops recording, removes its shortcuts and closes the overlay.
    private func setActive(_ active: Bool) {
        if active {
            monitor.start(recordingCurrent: !hasStarted)
            registerShortcuts(settings.shortcuts)
        } else {
            monitor.stop()
            registerShortcuts([])
            overlay.dismiss()
        }
        hasStarted = true
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
        let clear = NSMenuItem(title: String(localized: "Clear Clipboard History"), action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        return [clear]
    }

    /// The pane shown for this utility in Settings.
    func settingsPane() -> some View {
        ClipboardManagerPane(clipboard: settings, appearance: appearance, history: history)
    }

    @objc private func checkExpiry() {
        removeExpired(settings.expiry)
    }

    private func removeExpired(_ expiry: HistoryExpiry) {
        guard let interval = expiry.interval else { return }
        history.removeEntries(olderThan: Date().addingTimeInterval(-interval))
    }

    @objc private func clearHistory() {
        history.clear()
    }
}
