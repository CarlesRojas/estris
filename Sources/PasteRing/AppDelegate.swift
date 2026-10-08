import AppKit
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let history = ClipboardHistory()
    private var monitor: ClipboardMonitor!
    private var overlay: OverlayController!
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        monitor = ClipboardMonitor(history: history)
        overlay = OverlayController(history: history, monitor: monitor)
        monitor.start()
        setUpStatusItem()

        HotKeyCenter.shared.register(
            keyCode: UInt32(kVK_ANSI_V),
            modifiers: UInt32(cmdKey | shiftKey)
        ) { [weak self] in
            self?.overlay.cycle()
        }

        _ = Paster.isTrusted(prompt: true)
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Paste Ring")

        let menu = NSMenu()
        let title = NSMenuItem(title: "Paste Ring: ⌘⇧V to cycle", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        menu.addItem(makeItem("Clear History", #selector(clearHistory)))
        menu.addItem(makeItem("Grant Accessibility Access…", #selector(requestAccessibility)))
        menu.addItem(.separator())
        menu.addItem(makeItem("Quit Paste Ring", #selector(quit), key: "q"))
        statusItem.menu = menu
    }

    private func makeItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func clearHistory() {
        history.clear()
    }

    @objc private func requestAccessibility() {
        _ = Paster.isTrusted(prompt: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
