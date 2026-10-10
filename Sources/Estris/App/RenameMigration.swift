import Foundation

/// The app was called PasteRing, with its own bundle identifier. On the first launch as
/// Estris, its settings and its history carry over, so nothing is lost but the macOS
/// permissions, which are tied to the old identifier and must be granted again.
enum RenameMigration {
    private static let oldDomain = "com.carlesrojas.PasteRing"
    private static let oldFolder = "PasteRing"
    private static let doneKey = "migratedFromPasteRing"

    /// Runs before anything reads the settings or the history.
    static func run() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }
        defaults.set(true, forKey: doneKey)

        if let old = defaults.persistentDomain(forName: oldDomain) {
            for (key, value) in old where defaults.object(forKey: key) == nil {
                // Left out so the first launch adds Estris to the login items, as for a new
                // install: the old entry points at the old app.
                guard key != "didSetUpLoginItem" else { continue }
                defaults.set(value, forKey: key)
            }
        }

        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let from = support.appendingPathComponent(oldFolder, isDirectory: true)
        let to = support.appendingPathComponent("Estris", isDirectory: true)
        if FileManager.default.fileExists(atPath: from.path), !FileManager.default.fileExists(atPath: to.path) {
            do {
                try FileManager.default.moveItem(at: from, to: to)
            } catch {
                NSLog("Estris: failed to move the history from PasteRing: \(error)")
            }
        }
    }
}
