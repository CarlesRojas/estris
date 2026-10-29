import AppKit
import Combine
import SwiftUI

/// The menu bar item: the icon chosen in Settings > Menu Bar, and the frosted menu that a click
/// opens below it. A click outside the menu, Esc or another click on the icon closes it.
@MainActor
final class MenuBarController: NSObject {
    /// Room around the menu for its shadow.
    private static let shadowRoom: CGFloat = 24
    /// Between the menu bar and the menu.
    private static let gap: CGFloat = 8

    let settings = MenuBarSettings()
    private let volumeMixer: VolumeMixer
    private let clipboard: ClipboardManager
    private let colorPicker: ScreenColorPicker
    private let seasons: Seasons
    private let openSettings: () -> Void
    private var statusItem: NSStatusItem?
    private var panel: MenuBarPanel?
    private var observers: Set<AnyCancellable> = []
    private var clickMonitors: [Any] = []

    init(volumeMixer: VolumeMixer, clipboard: ClipboardManager, colorPicker: ScreenColorPicker, seasons: Seasons, openSettings: @escaping () -> Void) {
        self.seasons = seasons
        self.volumeMixer = volumeMixer
        self.clipboard = clipboard
        self.colorPicker = colorPicker
        self.openSettings = openSettings
    }

    func start() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(toggle)
        statusItem = item
        settings.$icon.combineLatest(settings.$iconColor)
            .sink { [weak self] icon, color in
                self?.statusItem?.button?.image = MenuBarIcon.image(for: icon, color: color.flatMap(NSColor.init(hex:)))
            }
            .store(in: &observers)
    }

    @objc private func toggle() {
        if panel?.isVisible == true {
            close()
        } else {
            open()
        }
    }

    private func open() {
        let panel = panel ?? makePanel()
        self.panel = panel
        let menu = MenuBarMenu(
            settings: settings,
            mixerSettings: volumeMixer.settings,
            mixerState: volumeMixer.state,
            mixer: volumeMixer,
            clipboardSettings: clipboard.settings,
            history: clipboard.history,
            colorPickerSettings: colorPicker.settings,
            seasonsSettings: seasons.settings,
            paste: { [weak self] item in
                // Closed first, so the paste goes to the app in front.
                self?.close()
                self?.clipboard.paste(item)
            },
            clearHistory: { [weak self] in self?.clipboard.history.clear() },
            pickColor: { [weak self] in
                self?.close()
                self?.colorPicker.pick()
            },
            copyColor: { [weak self] hex in
                self?.close()
                self?.colorPicker.copy(hex: hex)
            },
            openSettings: { [weak self] in
                self?.close()
                self?.openSettings()
            },
            quit: { NSApp.terminate(nil) },
            update: { [weak self] in
                self?.close()
                Updates.shared.checkForUpdates()
            }
        )
        let view = OverlayHostingView(rootView: menu
            .background(SizeReader { [weak self] size in self?.place(size) })
            .padding(Self.shadowRoom)
            .environmentObject(AppearanceSettings(usesDefaults: true)))
        panel.contentView = view
        let fitting = view.fittingSize
        place(CGSize(width: fitting.width - 2 * Self.shadowRoom, height: fitting.height - 2 * Self.shadowRoom))
        panel.makeKeyAndOrderFront(nil)

        // Clicks in other apps, and in Estris's own windows (Settings); not in the menu, its
        // pickers' pop-up menus or the icon, which toggles.
        let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                if event.window?.styleMask.contains(.titled) == true { self?.close() }
            }
            return event
        }
        clickMonitors = [global, local].compactMap { $0 }
    }

    private func close() {
        clickMonitors.forEach(NSEvent.removeMonitor)
        clickMonitors = []
        panel?.orderOut(nil)
        panel?.contentView = nil
    }

    private func makePanel() -> MenuBarPanel {
        let panel = MenuBarPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.onCancel = { [weak self] in self?.close() }
        return panel
    }

    /// The menu's size, without the room for its shadow, is `size`; it hangs below the icon,
    /// centred on it and kept on screen, and grows downwards.
    private func place(_ size: CGSize) {
        guard let panel, let button = statusItem?.button, let buttonWindow = button.window else { return }
        let anchor = buttonWindow.frame
        let screen = buttonWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let room = Self.shadowRoom
        let width = size.width + 2 * room
        let height = size.height + 2 * room
        var x = anchor.midX - width / 2
        x = min(max(x, screen.minX - room + 8), screen.maxX + room - 8 - width)
        let top = anchor.minY - Self.gap + room
        panel.setFrame(NSRect(x: x, y: top - height, width: width, height: height), display: true)
    }
}

/// Becomes key without activating Estris, so its controls and Esc work while the app in
/// front stays in front.
final class MenuBarPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
