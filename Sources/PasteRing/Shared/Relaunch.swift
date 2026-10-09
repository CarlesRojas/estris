import AppKit

/// Quits PasteRing and opens it again, for settings that apply at launch such as the language.
enum Relaunch {
    static func now() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Waits for this instance to quit before opening the app again.
        process.arguments = ["-c", "sleep 1; open \"$0\"", Bundle.main.bundlePath]
        try? process.run()
        NSApp.terminate(nil)
    }
}
