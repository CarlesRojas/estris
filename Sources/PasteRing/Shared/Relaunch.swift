import AppKit

/// Quits PasteRing and opens it again, for settings that apply at launch such as the language.
enum Relaunch {
    private static let reopenSettingsKey = "relaunchReopensSettings"

    /// With `reopeningSettings`, the Settings window opens again once relaunched.
    static func now(reopeningSettings: Bool = false) {
        UserDefaults.standard.set(reopeningSettings, forKey: reopenSettingsKey)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Waits for this instance to quit before opening the app again.
        process.arguments = ["-c", "sleep 1; open \"$0\"", Bundle.main.bundlePath]
        try? process.run()
        NSApp.terminate(nil)
    }

    /// Whether the last relaunch asked to reopen Settings; asking clears it.
    static func takeReopenSettings() -> Bool {
        let reopens = UserDefaults.standard.bool(forKey: reopenSettingsKey)
        UserDefaults.standard.removeObject(forKey: reopenSettingsKey)
        return reopens
    }
}
