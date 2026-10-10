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
    private lazy var keepAwake = KeepAwake(log: log)
    private let colorPicker = ScreenColorPicker()
    private lazy var volumeMixer = VolumeMixer(log: log)
    private var settingsWindow: SettingsWindowController?
    private lazy var menuBar = MenuBarController(volumeMixer: volumeMixer) { [weak self] in
        self?.openSettings()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        clipboard.start()
        autoQuit.start()
        middleClick.start()
        remap.start()
        windowSnapping.start()
        keepAwake.start()
        colorPicker.start()
        volumeMixer.start()
        menuBar.start()
        LoginItem.enableOnFirstLaunch()
        _ = Paster.isTrusted(prompt: true)
        // Relaunched from Settings (to change the language): back where the user was.
        if Relaunch.takeReopenSettings() {
            openSettings()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Key mappings set on keyboards outlive the app; take them back.
        remap.stop()
    }

    private func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(general: general, clipboard: clipboard, autoQuit: autoQuit, middleClick: middleClick, remap: remap, windowSnapping: windowSnapping, keepAwake: keepAwake, colorPicker: colorPicker, volumeMixer: volumeMixer, menuBarSettings: menuBar.settings, log: log)
        }
        settingsWindow?.show()
    }
}
