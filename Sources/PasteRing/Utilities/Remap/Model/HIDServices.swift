import Foundation

/// One input service (a keyboard or pointing interface) as the system's input event service
/// sees it. A device can have several, such as a keyboard with media keys.
struct HIDService {
    /// Matches the sender of the events this service produces.
    let registryID: UInt64
    let vendorID: Int
    let productID: Int
    let name: String
    let usagePage: Int
    let usage: Int
    fileprivate let client: AnyObject

    var isKeyboard: Bool { usagePage == 1 && usage == 6 }
    var isPointer: Bool { usagePage == 1 && (usage == 2 || usage == 1) }
}

/// The input event service calls, looked up at run time: they are in IOKit but not in its
/// Swift interface, or private.
enum HIDServices {
    private typealias CreateClient = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias CopyServices = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
    private typealias CopyProperty = @convention(c) (AnyObject, CFString) -> Unmanaged<AnyObject>?
    private typealias SetProperty = @convention(c) (AnyObject, CFString, AnyObject) -> UInt8
    private typealias GetRegistryID = @convention(c) (AnyObject) -> Unmanaged<AnyObject>?

    private static let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)

    private static func function<T>(_ name: String, as type: T.Type) -> T? {
        dlsym(iokit, name).map { unsafeBitCast($0, to: type) }
    }

    private static let client: AnyObject? = function("IOHIDEventSystemClientCreateSimpleClient", as: CreateClient.self)?(nil)?.takeRetainedValue()
    private static let copyServices = function("IOHIDEventSystemClientCopyServices", as: CopyServices.self)
    private static let copyProperty = function("IOHIDServiceClientCopyProperty", as: CopyProperty.self)
    private static let setProperty = function("IOHIDServiceClientSetProperty", as: SetProperty.self)
    private static let getRegistryID = function("IOHIDServiceClientGetRegistryID", as: GetRegistryID.self)

    /// Every keyboard and pointing service with a product name.
    static func all() -> [HIDService] {
        guard let client, let copyServices, let list = copyServices(client)?.takeRetainedValue() as? [AnyObject] else { return [] }
        return list.compactMap { service in
            guard let name = property(service, "Product") as? String, !name.isEmpty,
                  let registryID = (getRegistryID?(service)?.takeUnretainedValue() as? NSNumber)?.uint64Value
            else { return nil }
            let info = HIDService(
                registryID: registryID,
                vendorID: (property(service, "VendorID") as? NSNumber)?.intValue ?? 0,
                productID: (property(service, "ProductID") as? NSNumber)?.intValue ?? 0,
                name: name,
                usagePage: (property(service, "PrimaryUsagePage") as? NSNumber)?.intValue ?? 0,
                usage: (property(service, "PrimaryUsage") as? NSNumber)?.intValue ?? 0,
                client: service
            )
            return info.isKeyboard || info.isPointer ? info : nil
        }
    }

    @discardableResult
    static func set(_ key: String, to value: AnyObject, on service: HIDService) -> Bool {
        setProperty?(service.client, key as CFString, value) ?? 0 != 0
    }

    private static func property(_ service: AnyObject, _ key: String) -> AnyObject? {
        copyProperty?(service, key as CFString)?.takeRetainedValue()
    }
}

/// Reads which device an event came from, and its raw key, from the HID event macOS keeps
/// inside it. Private calls, looked up at run time; nil when they or the HID event are missing
/// (for example for events posted by apps).
enum EventSource {
    struct Key {
        let usagePage: Int
        let usage: Int
    }

    private typealias CopyHIDEvent = @convention(c) (CGEvent) -> Unmanaged<AnyObject>?
    private typealias GetSenderID = @convention(c) (AnyObject) -> UInt64
    private typealias GetType = @convention(c) (AnyObject) -> UInt32
    private typealias GetIntegerValue = @convention(c) (AnyObject, UInt32) -> Int

    private static let coreGraphics = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW)
    private static let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)

    private static let copyHIDEvent = dlsym(coreGraphics, "CGEventCopyIOHIDEvent").map { unsafeBitCast($0, to: CopyHIDEvent.self) }
    private static let getSenderID = dlsym(iokit, "IOHIDEventGetSenderID").map { unsafeBitCast($0, to: GetSenderID.self) }
    private static let getType = dlsym(iokit, "IOHIDEventGetType").map { unsafeBitCast($0, to: GetType.self) }
    private static let getIntegerValue = dlsym(iokit, "IOHIDEventGetIntegerValue").map { unsafeBitCast($0, to: GetIntegerValue.self) }

    /// The HID event type for keys, and its usage page and usage fields.
    private static let keyboardType: UInt32 = 3
    private static let usagePageField: UInt32 = 3 << 16
    private static let usageField: UInt32 = 3 << 16 | 1

    /// The input service that sent the event, matching `HIDService.registryID`.
    static func sender(of event: CGEvent) -> UInt64? {
        guard let hidEvent = copyHIDEvent?(event)?.takeRetainedValue(), let getSenderID else { return nil }
        let sender = getSenderID(hidEvent)
        return sender == 0 ? nil : sender
    }

    /// The HID key behind a key event.
    static func key(of event: CGEvent) -> Key? {
        guard let hidEvent = copyHIDEvent?(event)?.takeRetainedValue(),
              let getType, let getIntegerValue, getType(hidEvent) == keyboardType
        else { return nil }
        return Key(usagePage: getIntegerValue(hidEvent, usagePageField), usage: getIntegerValue(hidEvent, usageField))
    }
}
