import AppKit
import Sparkle

/// Updates through Sparkle. It reads the appcast published with each GitHub release, at launch
/// and every few hours. A newer version shows as "Update Available" at the top of the menu
/// bar menu instead of Sparkle's own window; installing opens Sparkle's window with the notes
/// and Install Update, which replaces the app and opens it again. Builds without the update
/// signing key in their Info.plist (local ones) don't check.
@MainActor
final class Updates: NSObject, ObservableObject {
    static let shared = Updates()

    /// The newer version found, if any.
    @Published private(set) var availableVersion: String?
    private var controller: SPUStandardUpdaterController?
    /// While Sparkle's windows are up: moves each to the screen the pointer is on.
    private var windowObserver: NSObjectProtocol?
    /// Windows already open, or already moved.
    private var knownWindows: Set<ObjectIdentifier> = []

    /// Whether this build can update itself.
    var canCheck: Bool { controller != nil }

    func start() {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        guard controller == nil, !key.isEmpty else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
        do {
            try controller.updater.start()
            self.controller = controller
        } catch {
            NSLog("Estris: updates can't start: \(error)")
        }
    }

    /// Shows Sparkle's window for the update found (or checks now), to install it.
    func checkForUpdates() {
        guard let controller else { return }
        followPointer()
        controller.checkForUpdates(nil)
    }

    /// Sparkle centres its windows on the main screen, which for a menu bar app isn't the one
    /// being used. Until the update session ends, each new window (checking, up to date, the
    /// update, its progress) moves to the middle of the screen with the pointer, once. Windows
    /// already open and Estris's own panels stay.
    private func followPointer() {
        stopFollowingPointer()
        knownWindows = Set(NSApp.windows.map(ObjectIdentifier.init))
        windowObserver = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let window = note.object as? NSWindow, !(window is MenuBarPanel), !(window is OverlayPanel),
                      self.knownWindows.insert(ObjectIdentifier(window)).inserted
                else { return }
                let mouse = NSEvent.mouseLocation
                guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }),
                      window.screen != screen
                else { return }
                let area = screen.visibleFrame
                window.setFrameOrigin(NSPoint(x: (area.midX - window.frame.width / 2).rounded(),
                                              y: (area.midY - window.frame.height / 2 + area.height / 6).rounded()))
            }
        }
    }

    private func stopFollowingPointer() {
        if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) }
        windowObserver = nil
    }
}

extension Updates: SPUUpdaterDelegate {
    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        MainActor.assumeIsolated { availableVersion = version }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        MainActor.assumeIsolated { availableVersion = nil }
    }
}

extension Updates: SPUStandardUserDriverDelegate {
    /// Scheduled checks don't open Sparkle's window: the menu shows the update instead.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        false
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { stopFollowingPointer() }
    }
}
