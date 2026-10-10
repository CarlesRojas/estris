import Foundation

/// How one app sounds: remembered for the next time it plays, also after quitting it.
struct AppSound: Codable, Equatable {
    /// 1 plays the app as it is; 0 is silent and 2 twice as loud.
    var volume: Double = 1
    var isMuted = false
    /// The device it plays on; nil follows the system output.
    var outputUID: String?
    /// The device's name, shown while it isn't connected.
    var outputName: String?

    /// Played as macOS would without PasteRing.
    var isUntouched: Bool { volume == 1 && !isMuted && outputUID == nil }
}

/// Volume Mixer preferences, persisted in UserDefaults.
@MainActor
final class VolumeMixerSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.isEnabled) }
    }

    /// By the app's bundle identifier, else its name.
    @Published var apps: [String: AppSound] {
        didSet { defaults.set(try? JSONEncoder().encode(apps), forKey: Keys.apps) }
    }

    init() {
        let defaults = UserDefaults.standard
        isEnabled = defaults.bool(forKey: Keys.isEnabled)
        apps = defaults.data(forKey: Keys.apps).flatMap { try? JSONDecoder().decode([String: AppSound].self, from: $0) } ?? [:]
    }

    func sound(of key: String) -> AppSound {
        apps[key] ?? AppSound()
    }

    func setSound(_ sound: AppSound, of key: String) {
        apps[key] = sound.isUntouched ? nil : sound
    }

    /// Every app back to playing as it is; the on/off switch stays.
    func reset() {
        apps = [:]
    }

    private enum Keys {
        static let isEnabled = "volumeMixerEnabled"
        static let apps = "volumeMixerApps"
    }
}
