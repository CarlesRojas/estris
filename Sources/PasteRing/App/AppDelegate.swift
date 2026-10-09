import AppKit
import SwiftUI

/// Creates the shared settings and every utility, and owns the menu bar item and the
/// Settings window. Each utility sets itself up in `start()`.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let general = GeneralSettings()
    private lazy var clipboard = ClipboardManager(general: general)
    private let log = AppLog()
    private lazy var autoQuit = AutoQuit(log: log)
    private lazy var middleClick = MiddleClick(log: log)
    private lazy var remap = Remap(log: log)
    private lazy var windowSnapping = WindowSnapping(log: log)
    private var settingsWindow: SettingsWindowController?
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        clipboard.start()
        autoQuit.start()
        middleClick.start()
        remap.start()
        windowSnapping.start()
        setUpStatusItem()
        LoginItem.enableOnFirstLaunch()
        _ = Paster.isTrusted(prompt: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Key mappings set on keyboards outlive the app; take them back.
        remap.stop()
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "PasteRing")

        let menu = NSMenu()
        let title = NSMenuItem(title: "PasteRing", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        menu.addItem(makeItem(String(localized: "Settings…"), #selector(openSettings), key: ","))
        menu.addItem(.separator())
        clipboard.menuItems().forEach(menu.addItem)
        menu.addItem(.separator())
        menu.addItem(makeItem(String(localized: "Quit PasteRing"), #selector(quit), key: "q"))
        statusItem.menu = menu
    }

    private func makeItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(general: general, clipboard: clipboard, autoQuit: autoQuit, middleClick: middleClick, remap: remap, windowSnapping: windowSnapping, log: log)
        }
        settingsWindow?.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
