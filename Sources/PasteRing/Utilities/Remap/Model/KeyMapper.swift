import Foundation

/// Applies key-to-key mappings on the keyboard itself, through the system's per-device key
/// mapping setting. Everything works as if the keyboard had the other key, modifiers and
/// Caps Lock included. macOS forgets the setting when a device reconnects, so it is applied
/// again then.
@MainActor
enum KeyMapper {
    private static let property = "UserKeyMapping"

    /// Devices given mappings, so they can be cleared later.
    private static var mappedDevices: Set<String> = []

    static func apply(_ settings: RemapSettings, devices: InputDevices) {
        var mapped: Set<String> = []
        if settings.isEnabled {
            for (deviceID, entry) in settings.devices {
                let pairs: [[String: NSNumber]] = entry.mappings.compactMap { mapping in
                    guard case .key(let source)? = mapping.input, case .key(let destination)? = mapping.output else { return nil }
                    return [
                        "HIDKeyboardModifierMappingSrc": NSNumber(value: source),
                        "HIDKeyboardModifierMappingDst": NSNumber(value: destination),
                    ]
                }
                guard !pairs.isEmpty else { continue }
                for service in devices.services(of: deviceID) {
                    HIDServices.set(property, to: pairs as NSArray, on: service)
                }
                mapped.insert(deviceID)
            }
        }
        for deviceID in mappedDevices.subtracting(mapped) {
            for service in devices.services(of: deviceID) {
                HIDServices.set(property, to: NSArray(), on: service)
            }
        }
        mappedDevices = mapped
    }

    static func clearAll(devices: InputDevices) {
        for deviceID in mappedDevices {
            for service in devices.services(of: deviceID) {
                HIDServices.set(property, to: NSArray(), on: service)
            }
        }
        mappedDevices = []
    }
}
