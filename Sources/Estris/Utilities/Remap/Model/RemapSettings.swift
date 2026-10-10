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
        case .nothing: String(localized: "Nothing")
        }
    }
}

/// A key or button and what it does instead. Either side is empty until chosen; an
/// incomplete mapping does nothing.
struct Mapping: Codable, Identifiable, Hashable {
    var id = UUID()
    var input: RemapInput?
    var output: RemapOutput?
    /// When it was added; the oldest wins when mappings on several devices compete.
    var created: Date? = Date()
}

/// A device's mappings, with its name kept so it still shows while disconnected.
struct DeviceMappings: Codable {
    var name: String
    var kind: InputDevice.Kind
    var mappings: [Mapping] = []
}

enum MappingConflict {
    case above
    case otherDevice(String)

    var message: String {
        switch self {
        case .above: String(localized: "Already mapped above")
        case .otherDevice(let name): String(localized: "Already mapped on \(name)")
        }
    }

    var explanation: String {
        switch self {
        case .above: String(localized: "Only the first mapping for a key or button applies.")
        case .otherDevice(let name): String(localized: "This button reaches macOS without saying which device sent it, so only the mapping on \(name) applies.")
        }
    }
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

    /// Keys and buttons seen reaching macOS without their device (some mice and utilities
    /// send them that way). Only one device's mapping can apply to each.
    @Published private(set) var deviceLessInputs: Set<RemapInput> {
        didSet { defaults.set(try? JSONEncoder().encode(deviceLessInputs), forKey: Keys.deviceLessInputs) }
    }

    /// Names given by the user, keyed by `InputDevice.id`.
    @Published var customNames: [String: String] {
        didSet { defaults.set(customNames, forKey: Keys.customNames) }
    }

    init() {
        let defaults = UserDefaults.standard
        isEnabled = defaults.bool(forKey: Keys.isEnabled)
        customNames = defaults.dictionary(forKey: Keys.customNames) as? [String: String] ?? [:]
        deviceLessInputs = defaults.data(forKey: Keys.deviceLessInputs).flatMap { try? JSONDecoder().decode(Set<RemapInput>.self, from: $0) } ?? []
        devices = defaults.data(forKey: Keys.devices).flatMap { try? JSONDecoder().decode([String: DeviceMappings].self, from: $0) } ?? [:]
        removeEmptyMappings()
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

    /// Returns true when the input wasn't known to arrive without its device.
    @discardableResult
    func noteDeviceLess(_ input: RemapInput) -> Bool {
        guard !deviceLessInputs.contains(input) else { return false }
        deviceLessInputs.insert(input)
        return true
    }

    /// For an input that arrives without its device: the device whose mapping applies, the
    /// one with the oldest complete mapping for it.
    func activeDevice(for input: RemapInput) -> (id: String, entry: DeviceMappings)? {
        devices
            .compactMap { id, entry -> (id: String, entry: DeviceMappings, created: Date)? in
                guard let mapping = entry.mappings.first(where: { $0.input == input }), mapping.output != nil else { return nil }
                return (id, entry, mapping.created ?? .distantPast)
            }
            .min { ($0.created, $0.id) < ($1.created, $1.id) }
            .map { ($0.id, $0.entry) }
    }

    /// Why a mapping doesn't apply, or nil when it does: an earlier row on the same device has
    /// the same key or button, or, for one that arrives without its device, another device's
    /// mapping wins.
    func conflict(for mapping: Mapping, on deviceID: String) -> MappingConflict? {
        guard let input = mapping.input else { return nil }
        if let first = mappings(for: deviceID).first(where: { $0.input == input }), first.id != mapping.id {
            return .above
        }
        guard deviceLessInputs.contains(input), let active = activeDevice(for: input), active.id != deviceID else { return nil }
        return .otherDevice(customNames[active.id] ?? active.entry.name)
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

    /// Changes a mapping. Another one for the same key or button stays; only the first applies.
    func update(_ mapping: Mapping, on deviceID: String) {
        guard var entry = devices[deviceID] else { return }
        guard let index = entry.mappings.firstIndex(where: { $0.id == mapping.id }) else { return }
        entry.mappings[index] = mapping
        devices[deviceID] = entry
    }

    /// Drops mappings with neither side chosen.
    func removeEmptyMappings() {
        for (id, entry) in devices where entry.mappings.contains(where: { $0.input == nil && $0.output == nil }) {
            devices[id]?.mappings.removeAll { $0.input == nil && $0.output == nil }
        }
    }

    func remove(_ mapping: Mapping, from deviceID: String) {
        devices[deviceID]?.mappings.removeAll { $0.id == mapping.id }
    }

    private enum Keys {
        static let isEnabled = "remapEnabled"
        static let devices = "remapDevices"
        static let customNames = "remapDeviceNames"
        // Renamed to forget inputs wrongly noted from events posted by apps.
        static let deviceLessInputs = "remapDeviceLessInputs2"
    }
}
