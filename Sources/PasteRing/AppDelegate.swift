import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let history = ClipboardHistory()
    private let settings = AppSettings()
    private var maxItemsObserver: AnyCancellable?
    private var preferencesWindow: NSWindow?
    private var monitor: ClipboardMonitor!
    private var overlay: OverlayController!
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        maxItemsObserver = settings.$maxItems.sink { [weak self] in
            self?.history.limit = $0
        }
        monitor = ClipboardMonitor(history: history)
        overlay = OverlayController(history: history, monitor: monitor, settings: settings)
        monitor.start()
        setUpStatusItem()

        HotKeyCenter.shared.register(
            keyCode: UInt32(kVK_ANSI_V),
            modifiers: UInt32(cmdKey | shiftKey)
        ) { [weak self] in
            self?.overlay.cycle()
        }

        LoginItem.enableOnFirstLaunch()
        _ = Paster.isTrusted(prompt: true)
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "PasteRing")

        let menu = NSMenu()
        let title = NSMenuItem(title: "PasteRing: ⌘⇧V to cycle", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        menu.addItem(makeItem("Settings…", #selector(openPreferences), key: ","))
        menu.addItem(makeItem("Clear History", #selector(clearHistory)))
        menu.addItem(makeItem("Grant Accessibility Access…", #selector(requestAccessibility)))
        menu.addItem(.separator())
        menu.addItem(makeItem("Quit PasteRing", #selector(quit), key: "q"))
        statusItem.menu = menu
    }

    private func makeItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func openPreferences() {
        if preferencesWindow == nil {
            // Toolbar tabs, like the system's own Settings windows.
            let tabs = NSTabViewController()
            tabs.tabStyle = .toolbar
            tabs.addTabViewItem(tab("General", symbol: "gearshape", GeneralPreferences(settings: settings)))
            tabs.addTabViewItem(tab("History", symbol: "clock", HistoryPreferences(history: history)))
            let window = NSWindow(contentViewController: tabs)
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            preferencesWindow = window
        }
        // Accessory apps are not activated automatically, so the window would open behind others.
        NSApp.activate(ignoringOtherApps: true)
        preferencesWindow?.makeKeyAndOrderFront(nil)
    }

    private func tab<Content: View>(_ label: String, symbol: String, _ view: Content) -> NSTabViewItem {
        let controller = NSHostingController(rootView: view)
        // The tab controller shows the selected tab's title as the window title.
        controller.title = label
        controller.sizingOptions = .preferredContentSize
        let item = NSTabViewItem(viewController: controller)
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
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
