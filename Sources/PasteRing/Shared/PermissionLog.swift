import AppKit
import ApplicationServices
import CoreGraphics

/// Logs what macOS says about each permission PasteRing could need, at launch and whenever it
/// changes (checked each time PasteRing comes to the front), to find the fewest it really
/// needs. For the logs only; nothing is asked.
@MainActor
final class PermissionLog {
    private let appLog: AppLog
    private var last = ""
    private var observer: NSObjectProtocol?

    init(log: AppLog) {
        appLog = log
    }

    func start() {
        record()
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.record() }
        }
    }

    private func record() {
        let summary = [
            "Accessibility: \(AXIsProcessTrusted() ? "allowed" : "not allowed")",
            "Screen Recording: \(CGPreflightScreenCaptureAccess() ? "allowed" : "not allowed")",
            "Input Monitoring: \(CGPreflightListenEventAccess() ? "allowed" : "not allowed")",
            "Post Events: \(CGPreflightPostEventAccess() ? "allowed" : "not allowed")",
            "System Audio Recording: \(Permission.systemAudioRecording.isGranted.map { $0 ? "allowed" : "not allowed" } ?? "not decided yet, or can't ask")",
        ].joined(separator: ", ")
        guard summary != last else { return }
        last = summary
        appLog.record(summary, source: "Permissions")
    }
}
