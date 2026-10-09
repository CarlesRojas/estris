import AppKit
import Combine
import SwiftUI

/// The Window Snapping utility: moves the front window to halves, corners, thirds or the
/// whole screen, with shortcuts or by dragging it to a screen edge.
/// Owns everything it needs, so the app only has to create it and call `start()`.
@MainActor
final class WindowSnapping {
    let settings = WindowSnappingSettings()
    private let appLog: AppLog
    private lazy var dragSnapper = DragSnapper(settings: settings) { [weak self] window, action, screen, original, fills in
        self?.snap(window, to: action, on: screen, from: original, fills: fills)
    }
    /// The last shortcut snap, so pressing it again on the same, unmoved window switches
    /// between the filled and the exact area.
    private var lastShortcut: (window: AXWindow, action: SnapAction, frame: NSRect, filled: Bool)?
    private var hotKeys: [UInt32] = []
    private var observers: Set<AnyCancellable> = []

    /// Each snapped window's frame before its first snap, for Restore, and the frame it was
    /// snapped to, to tell whether it was moved since.
    private var restoreFrames: [(window: AXWindow, original: NSRect, snapped: NSRect)] = []

    init(log: AppLog) {
        appLog = log
    }

    func start() {
        // Published values arrive before the property changes; applying on the next turn of
        // the run loop reads the new ones.
        settings.$isEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.apply() }
            .store(in: &observers)
    }

    /// The pane shown for this utility in Settings.
    func settingsPane() -> some View {
        WindowSnappingPane(settings: settings)
    }

    private func apply() {
        hotKeys.forEach(HotKeyCenter.shared.unregister)
        hotKeys = []
        guard settings.isEnabled else {
            dragSnapper.stop()
            return
        }
        dragSnapper.start()
        for action in SnapAction.allCases {
            let shortcut = action.shortcut
            hotKeys.append(HotKeyCenter.shared.register(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers) { [weak self] in
                self?.snapFocusedWindow(to: action)
            })
        }
    }

    private func snapFocusedWindow(to action: SnapAction) {
        guard let window = AXWindow.focused(), let frame = window.frame, let screen = window.screen else {
            return log("no window to snap (needs Accessibility access)")
        }
        var fills = settings.fillsSpace
        if fills, let last = lastShortcut, last.action == action, last.window.isSame(as: window),
           abs(last.frame.minX - frame.minX) < 2, abs(last.frame.minY - frame.minY) < 2,
           abs(last.frame.width - frame.width) < 2, abs(last.frame.height - frame.height) < 2 {
            fills = !last.filled
        }
        let result = snap(window, to: action, on: screen, from: frame, fills: fills)
        lastShortcut = result.map { (window, action, $0.frame, $0.filled) }
    }

    /// Moves a window; `original` is where it was before, kept for Restore. Returns where it
    /// ended up, and whether that is the filled area rather than the exact one.
    @discardableResult
    private func snap(_ window: AXWindow, to action: SnapAction, on screen: NSScreen, from original: NSRect, fills: Bool) -> (frame: NSRect, filled: Bool)? {
        let saved = restoreFrames.firstIndex { $0.window.isSame(as: window) }
        if action == .restore {
            guard let saved else { return nil }
            window.setFrame(restoreFrames[saved].original)
            restoreFrames.remove(at: saved)
            return nil
        }
        guard let current = window.frame, let usual = action.frame(in: screen, current: current) else { return nil }
        var target = usual
        if fills {
            let tiled = SpaceFiller.tiledWindows(on: screen, excluding: window)
            target = SpaceFiller.fit(usual, for: action, on: screen, among: tiled, pid: window.pid)
        }
        window.setFrame(target)
        // An app that won't get as small as the space gets the usual snap instead.
        if target != usual, SpaceFiller.refused(asked: target, got: window.frame, pid: window.pid) {
            target = usual
            window.setFrame(target)
        }
        // Apps can round the size, so what it ended up as is what a later move is compared to.
        let snapped = window.frame ?? target
        if let saved {
            // Moved by hand since its last snap: that is the frame to go back to now.
            if restoreFrames[saved].snapped != original { restoreFrames[saved].original = original }
            restoreFrames[saved].snapped = snapped
        } else {
            restoreFrames.append((window, original, snapped))
            if restoreFrames.count > 100 { restoreFrames.removeFirst() }
        }
        // Asked to fill but nothing to fill counts as exact, so a second press does nothing new.
        return (snapped, fills && target != usual)
    }

    private func log(_ message: String) {
        appLog.record(message, source: "Window Snapping")
    }
}
