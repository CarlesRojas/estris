import AppKit
import SwiftUI

/// The Settings window, laid out like System Settings: no title, and a fixed-width sidebar
/// running to the top of the window with the close, minimize and zoom buttons inside it.
///
/// The split is AppKit's own (`NSSplitViewController`): SwiftUI's `NavigationSplitView` always
/// lets the user drag the sidebar closed, while a split view item can be made not
/// collapsible. Both columns hold SwiftUI views.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private static let minimumSize = NSSize(width: 820, height: 600)
    private static let sidebarWidth: CGFloat = 215

    let window: NSWindow
    private let navigation: SettingsNavigation

    init(general: GeneralSettings, clipboard: ClipboardManager, autoQuit: AutoQuit, middleClick: MiddleClick, remap: Remap, windowSnapping: WindowSnapping, keepAwake: KeepAwake, colorPicker: ScreenColorPicker, log: AppLog) {
        let navigation = SettingsNavigation(general: general)
        self.navigation = navigation
        let sidebar = NSHostingController(rootView: SettingsSidebar(navigation: navigation, clipboardSettings: clipboard.settings, autoQuitSettings: autoQuit.settings, middleClickSettings: middleClick.settings, remapSettings: remap.settings, windowSnappingSettings: windowSnapping.settings, keepAwakeSettings: keepAwake.settings, colorPickerSettings: colorPicker.settings))
        let detail = NSHostingController(rootView: SettingsDetail(navigation: navigation, general: general, clipboard: clipboard, autoQuit: autoQuit, middleClick: middleClick, remap: remap, windowSnapping: windowSnapping, keepAwake: keepAwake, colorPicker: colorPicker, log: log))
        // The window sets its own size; SwiftUI content must not grow or shrink it.
        sidebar.sizingOptions = []
        detail.sizingOptions = []

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.canCollapse = false
        sidebarItem.minimumThickness = Self.sidebarWidth
        sidebarItem.maximumThickness = Self.sidebarWidth
        let detailItem = NSSplitViewItem(viewController: detail)

        let split = NSSplitViewController()
        split.addSplitViewItem(sidebarItem)
        split.addSplitViewItem(detailItem)

        window = NSWindow(contentViewController: split)
        super.init()

        window.title = ""
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbar = NSToolbar(identifier: "Settings")
        window.toolbarStyle = .unified
        // 80% of the screen's height, within sensible limits.
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 800
        window.setContentSize(NSSize(width: 880, height: min(max(screenHeight * 0.8, 640), 1100)))
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
    }

    func show() {
        // Accessory apps are not activated automatically, so the window would open behind others.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        // Applied after showing: the split view sets its own limits once laid out.
        window.contentMinSize = Self.minimumSize
        window.minSize = minimumFrameSize
        // Don't start with a text field focused (and its contents selected).
        window.makeFirstResponder(nil)
    }

    private var minimumFrameSize: NSSize {
        window.frameRect(forContentRect: NSRect(origin: .zero, size: Self.minimumSize)).size
    }

    /// Last line of defence for the minimum size, whatever else changes the window's limits.
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        NSSize(width: max(frameSize.width, minimumFrameSize.width), height: max(frameSize.height, minimumFrameSize.height))
    }
}
