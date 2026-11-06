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

    /// The vendor and product an id was made from.
    static func vendorAndProduct(of id: String) -> (vendorID: Int, productID: Int)? {
        let parts = id.split(separator: "-", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, let vendor = Int(parts[0]), let product = Int(parts[1]) else { return nil }
        return (vendor, product)
    }
}

/// The connected keyboards and mice, and which device each input service belongs to.
@MainActor
final class InputDevices: ObservableObject {
    @Published private(set) var connected: [InputDevice] = []
    private(set) var services: [HIDService] = []
    private var deviceBySender: [UInt64: InputDevice] = [:]

    /// Lists the devices again. `known` are the devices with mappings, by id and name: a
    /// service without a product name yet (a wireless keyboard just after the Mac starts) is
    /// taken as the known device with its vendor and product, so its mappings still apply.
    func refresh(known: [String: String] = [:]) {
        services = HIDServices.all()
        let knownByModel = Dictionary(known.compactMap { id, name in
            InputDevice.vendorAndProduct(of: id).map { ("\($0.vendorID)-\($0.productID)", (id: id, name: name)) }
        }, uniquingKeysWith: { first, _ in first })
        var names: [String: String] = [:]
        var physical: [String: [HIDService]] = [:]
        for service in services {
            let id: String
            if !service.name.isEmpty {
                id = InputDevice.id(vendorID: service.vendorID, productID: service.productID, name: service.name)
                names[id] = service.name
            } else if service.vendorID != 0, let match = knownByModel["\(service.vendorID)-\(service.productID)"] {
                id = match.id
                names[id] = names[id] ?? match.name
            } else {
                continue
            }
            physical[id, default: []].append(service)
        }
        var devices: [InputDevice] = []
        var bySender: [UInt64: InputDevice] = [:]
        for (id, group) in physical {
            // One entry per physical device: everything it sends can be remapped there. The
            // kind only picks its icon and which inputs the picker lists first.
            let name = names[id] ?? group[0].name
            let hasKeyboard = group.contains(where: \.isKeyboard)
            let hasPointer = group.contains(where: \.isPointer)
            // Only keyboards and pointing devices are listed, but every interface of one maps
            // to it: a mouse can send its side buttons through another one.
            guard hasKeyboard || hasPointer else { continue }
            let isKeyboard = hasKeyboard && (!hasPointer || name.localizedCaseInsensitiveContains("keyboard"))
            let device = InputDevice(id: id, name: name, kind: isKeyboard ? .keyboard : .mouse)
            devices.append(device)
            for service in group {
                bySender[service.registryID] = device
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
}
