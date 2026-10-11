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
        controller?.checkForUpdates(nil)
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
}
