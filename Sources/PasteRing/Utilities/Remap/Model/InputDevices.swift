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
        var devices: [String: InputDevice] = [:]
        var bySender: [UInt64: InputDevice] = [:]
        for service in services {
            let id = InputDevice.id(vendorID: service.vendorID, productID: service.productID, name: service.name)
            // A device with a keyboard interface is listed as a keyboard, even if it also points.
            let kind: InputDevice.Kind = service.isKeyboard ? .keyboard : .mouse
            if devices[id] == nil || kind == .keyboard {
                devices[id] = InputDevice(id: id, name: service.name, kind: kind)
            }
        }
        for service in services {
            let id = InputDevice.id(vendorID: service.vendorID, productID: service.productID, name: service.name)
            bySender[service.registryID] = devices[id]
        }
        deviceBySender = bySender
        connected = devices.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func device(sender: UInt64) -> InputDevice? {
        deviceBySender[sender]
    }

    func services(of deviceID: String) -> [HIDService] {
        services.filter { InputDevice.id(vendorID: $0.vendorID, productID: $0.productID, name: $0.name) == deviceID }
    }
}
