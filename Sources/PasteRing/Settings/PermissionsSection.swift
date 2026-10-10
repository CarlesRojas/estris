import AppKit
import CoreGraphics
import SwiftUI

/// A macOS permission a utility asks for.
enum Permission {
    case accessibility
    case screenRecording
    case systemAudioRecording

    var title: LocalizedStringKey {
        switch self {
        case .accessibility: "Accessibility"
        case .screenRecording: "Screen Recording"
        case .systemAudioRecording: "System Audio Recording"
        }
    }

    var symbol: String {
        switch self {
        case .accessibility: "accessibility"
        case .screenRecording: "rectangle.dashed.badge.record"
        case .systemAudioRecording: "waveform"
        }
    }

    /// Its page in System Settings > Privacy & Security.
    var settingsURL: URL {
        switch self {
        case .accessibility: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        case .screenRecording, .systemAudioRecording: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        }
    }

    /// Nil when it can't be told.
    var isGranted: Bool? {
        switch self {
        case .accessibility: AXIsProcessTrusted()
        case .screenRecording: CGPreflightScreenCaptureAccess()
        case .systemAudioRecording: Self.privacyDatabase("kTCCServiceAudioCapture")
        }
    }

    /// What the privacy database says, through `TCCAccessPreflight`: macOS has no public way to
    /// read System Audio Recording. Looked up at run time; nil if it's missing or undecided.
    private static func privacyDatabase(_ service: String) -> Bool? {
        guard let preflight else { return nil }
        switch preflight(service as CFString, nil) {
        case 0: return true
        case 1: return false
        default: return nil
        }
    }

    private static let preflight: (@convention(c) (CFString, CFDictionary?) -> Int32)? = {
        guard let framework = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW),
              let symbol = dlsym(framework, "TCCAccessPreflight")
        else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (CFString, CFDictionary?) -> Int32).self)
    }()
}

extension Permission {
    /// Asks macOS for it: its own prompt the first time, its System Settings page after that
    /// (macOS only prompts once), and the page directly for System Audio Recording, which has
    /// no public way to ask.
    @MainActor
    func request() {
        switch self {
        case .accessibility:
            // macOS's prompt, with a button to the page.
            _ = Paster.isTrusted(prompt: true)
        case .screenRecording:
            let key = "askedForScreenRecording"
            if UserDefaults.standard.bool(forKey: key) {
                NSWorkspace.shared.open(settingsURL)
            } else {
                UserDefaults.standard.set(true, forKey: key)
                CGRequestScreenCaptureAccess()
            }
        case .systemAudioRecording:
            NSWorkspace.shared.open(settingsURL)
        }
    }
}

/// A permission, in plain words the one thing it is used for, and what still works without it.
struct PermissionUse {
    let permission: Permission
    let reason: LocalizedStringKey
    /// Shown while it isn't allowed.
    let without: LocalizedStringKey
}

/// The first section of the settings of a utility that needs permissions: which, what for, and
/// what still works without each. Each shows whether it is allowed, with a button to its System
/// Settings page when it isn't.
/// Utilities that need none don't show it.
struct PermissionsSection: View {
    let uses: [PermissionUse]
    /// Bumped to read the permissions again after returning from System Settings.
    @State private var refresh = 0

    var body: some View {
        Section("Permissions") {
            ForEach(Array(uses.enumerated()), id: \.offset) { _, use in
                row(use)
            }
        }
        .id(refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh += 1
        }
    }

    private func row(_ use: PermissionUse) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: use.permission.symbol)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(use.permission.title)
                Text(use.reason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if use.permission.isGranted != true {
                    Text(use.without)
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if use.permission.isGranted == true {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .labelStyle(.titleAndIcon)
            } else {
                Button("Open System Settings") {
                    // macOS only lists an app under Screen Recording once it has asked.
                    if use.permission == .screenRecording { CGRequestScreenCaptureAccess() }
                    NSWorkspace.shared.open(use.permission.settingsURL)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
