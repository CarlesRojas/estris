import AppKit
import CoreServices
import SwiftUI

/// Creates the shared settings and every utility, and owns the menu bar item and the
/// Settings window. Each utility sets itself up in `start()`.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let general = GeneralSettings()
    private lazy var clipboard = ClipboardManager(general: general)
    private let log = AppLog()
    private lazy var permissionLog = PermissionLog(log: log)
    private lazy var autoQuit = AutoQuit(log: log)
    private lazy var middleClick = MiddleClick(log: log)
    private lazy var deleteToTrash = DeleteToTrash(log: log)
    private lazy var remap = Remap(log: log)
    private lazy var windowSnapping = WindowSnapping(log: log)
    private lazy var focusFollowsMouse = FocusFollowsMouse(log: log)
    private lazy var dockPreview = DockPreview(log: log)
    private lazy var keepAwake = KeepAwake(log: log)
    private let roundedCorners = RoundedCorners()
    private let colorPicker = ScreenColorPicker()
    private lazy var volumeMixer = VolumeMixer(log: log)
    private var settingsWindow: SettingsWindowController?
    /// Opened by macOS at login, rather than by the user.
    private var launchedAtLogin = false
    private var accessibilityWatch: Timer?
    private lazy var menuBar = MenuBarController(volumeMixer: volumeMixer, clipboard: clipboard, colorPicker: colorPicker) { [weak self] in
        self?.openSettings()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        let event = NSAppleEventManager.shared().currentAppleEvent
        launchedAtLogin = event?.eventID == AEEventID(kAEOpenApplication)
            && event?.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Opened from the disk image: moving to Applications opens it again from there.
        if ApplicationsMover.offerIfNeeded() { return }
        ApplicationsMover.ejectInstallerDiskImage()
        permissionLog.start()
        clipboard.start()
        autoQuit.start()
        middleClick.start()
        deleteToTrash.start()
        remap.start()
        windowSnapping.start()
        focusFollowsMouse.start()
        dockPreview.start()
        keepAwake.start()
        roundedCorners.start()
        colorPicker.start()
        volumeMixer.start()
        menuBar.start()
        Updates.shared.start()
        // Only from where it stays: a login item for the disk image would break once it's ejected.
        if !ApplicationsMover.isOutsideApplications {
            LoginItem.enableOnFirstLaunch()
        }
        watchAccessibility()
        // Opened by the user (not at login): Settings, to choose what to turn on. Also after a
        // relaunch from Settings, back where the user was.
        let reopensSettings = Relaunch.takeReopenSettings()
        if reopensSettings || !launchedAtLogin {
            openSettings()
        }
    }

    /// Opened again while running (a double-click in Applications): Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    /// Utilities set up their event taps and window access at launch, which fails without
    /// Accessibility; once it is allowed, Estris opens again so they work, without anyone
    /// having to quit it.
    private func watchAccessibility() {
        guard !AXIsProcessTrusted() else { return }
        accessibilityWatch = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard AXIsProcessTrusted() else { return }
                timer.invalidate()
                self?.log.record("Accessibility allowed: opening again", source: "Permissions")
                Relaunch.now(reopeningSettings: self?.settingsWindow?.window.isVisible == true)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Key mappings set on keyboards outlive the app; take them back.
        remap.stop()
        // An automatically hidden Dock held showing by Dock Preview hides itself again.
        DockHold.end()
    }

    private func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(general: general, clipboard: clipboard, autoQuit: autoQuit, middleClick: middleClick, deleteToTrash: deleteToTrash, remap: remap, windowSnapping: windowSnapping, focusFollowsMouse: focusFollowsMouse, dockPreview: dockPreview, keepAwake: keepAwake, roundedCorners: roundedCorners, colorPicker: colorPicker, volumeMixer: volumeMixer, menuBarSettings: menuBar.settings, log: log)
        }
        settingsWindow?.show()
    }
}
