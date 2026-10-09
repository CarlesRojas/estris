import AppKit

/// An app found on this Mac.
struct InstalledApp: Identifiable, Hashable, Sendable {
    let bundleID: String
    let name: String
    let url: URL

    var id: String { bundleID }
}

enum InstalledApps {
    /// Apps in the usual Applications folders, one level of subfolders deep (such as
    /// Utilities), sorted by name. Reads bundles from disk, so call it off the main thread.
    static func scan() -> [InstalledApp] {
        let fileManager = FileManager.default
        let roots = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
        ]
        var found: [String: InstalledApp] = [:]
        for root in roots {
            let entries = (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            for entry in entries {
                if entry.pathExtension == "app" {
                    add(entry, to: &found)
                } else if (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    let nested = (try? fileManager.contentsOfDirectory(at: entry, includingPropertiesForKeys: nil)) ?? []
                    nested.filter { $0.pathExtension == "app" }.forEach { add($0, to: &found) }
                }
            }
        }
        return found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func add(_ url: URL, to found: inout [String: InstalledApp]) {
        guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier, found[bundleID] == nil else { return }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        found[bundleID] = InstalledApp(bundleID: bundleID, name: name, url: url)
    }
}
