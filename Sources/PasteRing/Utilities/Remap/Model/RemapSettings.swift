import Foundation

/// What a mapping is triggered by.
enum RemapInput: Codable, Hashable {
    /// A key, by its HID usage (page in the upper 32 bits).
    case key(UInt64)
    /// A mouse button, by number (1 is the right button).
    case mouseButton(Int)

    var title: String {
        switch self {
        case .key(let usage): KeyCatalog.name(usage: usage)
        case .mouseButton(let number): MouseButtons.name(number)
        }
    }
}

/// What a mapping does instead.
enum RemapOutput: Codable, Hashable {
    case key(UInt64)
    case mouseButton(Int)
    case action(SystemAction)
    /// Nothing: the key or button is turned off.
    case nothing

    var title: String {
        switch self {
        case .key(let usage): KeyCatalog.name(usage: usage)
        case .mouseButton(let number): MouseButtons.name(number)
        case .action(let action): action.title
        case .nothing: "Nothing"
        }
    }
}

struct Mapping: Codable, Identifiable, Hashable {
    var id = UUID()
    var input: RemapInput
    var output: RemapOutput
}

/// A device's mappings, with its name kept so it still shows while disconnected.
struct DeviceMappings: Codable {
    var name: String
    var kind: InputDevice.Kind
    var mappings: [Mapping] = []
}

/// Remap preferences, persisted in UserDefaults.
@MainActor
final class RemapSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.isEnabled) }
    }

    /// Mappings per device, keyed by `InputDevice.id`.
    @Published var devices: [String: DeviceMappings] {
        didSet { defaults.set(try? JSONEncoder().encode(devices), forKey: Keys.devices) }
    }

    init() {
        let defaults = UserDefaults.standard
        isEnabled = defaults.bool(forKey: Keys.isEnabled)
        devices = defaults.data(forKey: Keys.devices).flatMap { try? JSONDecoder().decode([String: DeviceMappings].self, from: $0) } ?? [:]
    }

    func mappings(for deviceID: String) -> [Mapping] {
        devices[deviceID]?.mappings ?? []
    }

    /// Adds a mapping, replacing any other one for the same key or button.
    func add(_ mapping: Mapping, to device: InputDevice) {
        var entry = devices[device.id] ?? DeviceMappings(name: device.name, kind: device.kind)
        entry.name = device.name
        entry.mappings.removeAll { $0.input == mapping.input }
        entry.mappings.append(mapping)
        devices[device.id] = entry
    }

    func update(_ mapping: Mapping, on deviceID: String) {
        guard var entry = devices[deviceID] else { return }
        entry.mappings.removeAll { $0.input == mapping.input && $0.id != mapping.id }
        guard let index = entry.mappings.firstIndex(where: { $0.id == mapping.id }) else { return }
        entry.mappings[index] = mapping
        devices[deviceID] = entry
    }

    func remove(_ mapping: Mapping, from deviceID: String) {
        devices[deviceID]?.mappings.removeAll { $0.id == mapping.id }
    }

    private enum Keys {
        static let isEnabled = "remapEnabled"
        static let devices = "remapDevices"
    }
}
