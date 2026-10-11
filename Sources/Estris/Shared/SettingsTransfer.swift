import Foundation

/// Saves Estris's settings to a JSON file and reads them back, on this Mac or another. Covers
/// everything Estris keeps in UserDefaults except state tied to this Mac (permission hints,
/// login item setup, one-off migrations); the clipboard history and Open at login aren't
/// settings there, so they stay out too.
enum SettingsTransfer {
    private static let format = "Estris settings"
    private static let formatVersion = 1
    /// Not settings: what this Mac has seen or done once.
    private static let machineKeys: Set<String> = [
        "didSetUpLoginItem", "migratedFromPasteRing", "relaunchReopensSettings", "heardSystemAudio",
        "dockPreviewRestoreAutohide", "remapDeviceLessInputs2",
    ]

    enum TransferError: LocalizedError {
        case notSettings

        var errorDescription: String? {
            String(localized: "This file isn't an Estris settings file.")
        }
    }

    static var suggestedFileName: String { "Estris Settings.json" }

    /// The settings as pretty-printed JSON.
    static func exportData() throws -> Data {
        let settings = storedSettings.mapValues(encode)
        let root: [String: Any] = [
            "format": format,
            "version": formatVersion,
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            "settings": settings,
        ]
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    /// Replaces the current settings with the file's. They apply once Estris opens again.
    static func importData(_ data: Data) throws {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["format"] as? String == format,
              let settings = root["settings"] as? [String: Any]
        else { throw TransferError.notSettings }
        let defaults = UserDefaults.standard
        for key in storedSettings.keys {
            defaults.removeObject(forKey: key)
        }
        for (key, value) in settings where isSetting(key) {
            if let value = decode(value) { defaults.set(value, forKey: key) }
        }
    }

    private static var storedSettings: [String: Any] {
        let domain = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "com.carlesrojas.Estris") ?? [:]
        return domain.filter { isSetting($0.key) }
    }

    /// Estris's own keys, plus the app's language; not what macOS adds (window frames and such).
    private static func isSetting(_ key: String) -> Bool {
        if key == "AppleLanguages" { return true }
        return !machineKeys.contains(key) && !["NS", "Apple", "com.apple"].contains { key.hasPrefix($0) }
    }

    // MARK: Values
    // JSON has no data or dates: they are wrapped in a one-key object. Data holding JSON (most
    // settings stored as Codable) stays readable.

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func encode(_ value: Any) -> Any {
        switch value {
        case let data as Data:
            if let json = try? JSONSerialization.jsonObject(with: data), json is [Any] || json is [String: Any] {
                return ["$json": json]
            }
            return ["$data": data.base64EncodedString()]
        case let date as Date:
            return ["$date": dateFormatter.string(from: date)]
        case let array as [Any]:
            return array.map(encode)
        case let dictionary as [String: Any]:
            return dictionary.mapValues(encode)
        default:
            return value
        }
    }

    private static func decode(_ value: Any) -> Any? {
        switch value {
        case let dictionary as [String: Any]:
            if dictionary.count == 1, let json = dictionary["$json"] {
                return try? JSONSerialization.data(withJSONObject: json)
            }
            if dictionary.count == 1, let base64 = dictionary["$data"] as? String {
                return Data(base64Encoded: base64)
            }
            if dictionary.count == 1, let date = dictionary["$date"] as? String {
                return dateFormatter.date(from: date)
            }
            return dictionary.compactMapValues(decode)
        case let array as [Any]:
            return array.compactMap(decode)
        case is NSNull:
            return nil
        default:
            return value
        }
    }
}
