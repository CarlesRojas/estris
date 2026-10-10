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
            "System Audio Recording: \(Self.tcc("kTCCServiceAudioCapture"))",
        ].joined(separator: ", ")
        guard summary != last else { return }
        last = summary
        appLog.record(summary, source: "Permissions")
    }

    /// What the privacy database says for a service, through `TCCAccessPreflight` (private, the
    /// only way to read System Audio Recording); looked up at run time.
    private static func tcc(_ service: String) -> String {
        guard let preflight else { return "unknown (can't ask)" }
        switch preflight(service as CFString, nil) {
        case 0: return "allowed"
        case 1: return "not allowed"
        default: return "not decided yet"
        }
    }

    private static let preflight: (@convention(c) (CFString, CFDictionary?) -> Int32)? = {
        guard let framework = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW),
              let symbol = dlsym(framework, "TCCAccessPreflight")
        else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (CFString, CFDictionary?) -> Int32).self)
    }()
}
