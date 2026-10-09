import Foundation

/// Sets how fast the pointer moves, for mice and trackpads separately.
///
/// The speed is handed straight to the system's input event service, the way System Settings
/// does it, so it takes effect at once. It isn't saved there, so macOS forgets it when a
/// device reconnects or the Mac wakes; `Mouse` sets it again then.
enum PointerSpeed {
    enum Device {
        case mouse
        case trackpad

        /// The input service's setting for this device.
        fileprivate var property: String {
            switch self {
            case .mouse: "HIDMouseAcceleration"
            case .trackpad: "HIDTrackpadAcceleration"
            }
        }

        /// Where System Settings saves its speed.
        fileprivate var preference: String {
            switch self {
            case .mouse: "com.apple.mouse.scaling"
            case .trackpad: "com.apple.trackpad.scaling"
            }
        }
    }

    /// The speed set in System Settings (its slider goes from 0 to 3).
    static func systemSpeed(of device: Device) -> Double {
        let value = CFPreferencesCopyValue(device.preference as CFString, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        return (value as? NSNumber)?.doubleValue ?? 1
    }

    /// Sets the speed, or puts back the System Settings one when `speed` is nil.
    @discardableResult
    static func apply(_ speed: Double?, to device: Device) -> Bool {
        guard let client = EventSystem.client, let setProperty = EventSystem.setProperty else { return false }
        // The service reads the speed as a fixed-point number with 16 fractional bits.
        let value = NSNumber(value: Int((speed ?? systemSpeed(of: device)) * 65536))
        return setProperty(client, device.property as CFString, value) != 0
    }

    /// The input event service calls, looked up at run time: they are in IOKit but not in
    /// its Swift interface.
    private enum EventSystem {
        private typealias CreateClient = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
        typealias SetProperty = @convention(c) (AnyObject, CFString, AnyObject) -> UInt8

        private static let library = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)

        static let client: AnyObject? = {
            guard let symbol = dlsym(library, "IOHIDEventSystemClientCreateSimpleClient"),
                  let created = unsafeBitCast(symbol, to: CreateClient.self)(nil)
            else { return nil }
            return created.takeRetainedValue()
        }()

        static let setProperty: SetProperty? = dlsym(library, "IOHIDEventSystemClientSetProperty")
            .map { unsafeBitCast($0, to: SetProperty.self) }
    }
}
