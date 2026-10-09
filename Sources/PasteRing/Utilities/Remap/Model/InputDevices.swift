import Foundation

/// A keyboard or pointing device, made of one or more input services.
struct InputDevice: Identifiable, Hashable {
    enum Kind: String, Codable {
        case keyboard
        case mouse
    }

    /// Vendor and product, so a device keeps its mappings across reconnects.
    let id: String
    let name: String
    let kind: Kind
    var isConnected = true

    var symbol: String {
        if kind == .keyboard { return "keyboard" }
        return name.localizedCaseInsensitiveContains("trackpad") ? "rectangle.and.hand.point.up.left" : "computermouse"
    }

    static func id(vendorID: Int, productID: Int, name: String) -> String {
        "\(vendorID)-\(productID)-\(name)"
    }
}

/// The connected keyboards and mice, and which device each input service belongs to.
@MainActor
final class InputDevices: ObservableObject {
    @Published private(set) var connected: [InputDevice] = []
    private(set) var services: [HIDService] = []
    private var deviceBySender: [UInt64: InputDevice] = [:]

    func refresh() {
        services = HIDServices.all()
        let physical = Dictionary(grouping: services) {
            InputDevice.id(vendorID: $0.vendorID, productID: $0.productID, name: $0.name)
        }
        var devices: [InputDevice] = []
        var bySender: [UInt64: InputDevice] = [:]
        for (id, group) in physical {
            let name = group[0].name
            let hasKeyboard = group.contains(where: \.isKeyboard)
            let hasPointer = group.contains(where: \.isPointer)
            if hasKeyboard, hasPointer {
                // A keyboard with a built-in trackpad, or one receiver for a keyboard and a
                // mouse: listed as both, each with the services of its kind.
                let keyboard = InputDevice(id: id, name: Self.keyboardName(name), kind: .keyboard)
                let pointer = InputDevice(id: id + "-pointer", name: Self.pointerName(name), kind: .mouse)
                devices += [keyboard, pointer]
                for service in group {
                    bySender[service.registryID] = service.isPointer ? pointer : keyboard
                }
            } else {
                let device = InputDevice(id: id, name: name, kind: hasPointer ? .mouse : .keyboard)
                devices.append(device)
                for service in group {
                    bySender[service.registryID] = device
                }
            }
        }
        deviceBySender = bySender
        connected = devices.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func device(sender: UInt64) -> InputDevice? {
        deviceBySender[sender]
    }

    func services(of deviceID: String) -> [HIDService] {
        services.filter { deviceBySender[$0.registryID]?.id == deviceID }
    }

    /// "Apple Internal Keyboard / Trackpad" becomes "Apple Internal Keyboard", and
    /// "USB Receiver" becomes "USB Receiver (Keyboard)".
    private static func keyboardName(_ name: String) -> String {
        let parts = name.components(separatedBy: " / ")
        return parts.count > 1 ? parts[0] : name + " (Keyboard)"
    }

    /// "Apple Internal Keyboard / Trackpad" becomes "Apple Internal Trackpad", and
    /// "USB Receiver" becomes "USB Receiver (Mouse)".
    private static func pointerName(_ name: String) -> String {
        let parts = name.components(separatedBy: " / ")
        guard parts.count > 1 else { return name + " (Mouse)" }
        var words = parts[0].components(separatedBy: " ")
        words.removeLast()
        return (words + [parts[1]]).joined(separator: " ")
    }
}
