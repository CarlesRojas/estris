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

/// A key or button and what it does instead. Either side is empty until chosen; an
/// incomplete mapping does nothing.
struct Mapping: Codable, Identifiable, Hashable {
    var id = UUID()
    var input: RemapInput?
    var output: RemapOutput?
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

    /// Names given by the user, keyed by `InputDevice.id`.
    @Published var customNames: [String: String] {
        didSet { defaults.set(customNames, forKey: Keys.customNames) }
    }

    init() {
        let defaults = UserDefaults.standard
        isEnabled = defaults.bool(forKey: Keys.isEnabled)
        customNames = defaults.dictionary(forKey: Keys.customNames) as? [String: String] ?? [:]
        devices = defaults.data(forKey: Keys.devices).flatMap { try? JSONDecoder().decode([String: DeviceMappings].self, from: $0) } ?? [:]
    }

    /// The device's name, as renamed by the user if it was.
    func name(of device: InputDevice) -> String {
        customNames[device.id] ?? device.name
    }

    /// Renames a device; an empty name goes back to the one it reports.
    func rename(_ deviceID: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        customNames[deviceID] = trimmed.isEmpty ? nil : trimmed
    }

    func mappings(for deviceID: String) -> [Mapping] {
        devices[deviceID]?.mappings ?? []
    }

    /// Adds an empty mapping at the end of the device's list.
    func addMapping(to device: InputDevice) {
        var entry = devices[device.id] ?? DeviceMappings(name: device.name, kind: device.kind)
        entry.name = device.name
        entry.mappings.append(Mapping())
        devices[device.id] = entry
    }

    /// Adds a mapping from a key or button, unless the device already has one for it.
    func addMapping(from input: RemapInput, to device: InputDevice) {
        guard !mappings(for: device.id).contains(where: { $0.input == input }) else { return }
        var entry = devices[device.id] ?? DeviceMappings(name: device.name, kind: device.kind)
        entry.mappings.append(Mapping(input: input))
        devices[device.id] = entry
    }

    /// Changes a mapping, removing any other one for the same key or button.
    func update(_ mapping: Mapping, on deviceID: String) {
        guard var entry = devices[deviceID] else { return }
        if mapping.input != nil {
            entry.mappings.removeAll { $0.input == mapping.input && $0.id != mapping.id }
        }
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
        static let customNames = "remapDeviceNames"
    }
}
