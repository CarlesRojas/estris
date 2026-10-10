import AudioToolbox
import CoreAudio
import Foundation

/// A sound output or input device, such as the MacBook speakers or a headset.
struct AudioDevice: Identifiable, Hashable {
    let id: AudioObjectID
    let uid: String
    let name: String
}

/// Reads and changes the Mac's audio devices through CoreAudio.
enum AudioSystem {
    static let system = AudioObjectID(kAudioObjectSystemObject)
    /// The devices Estris creates to play an app's sound; never listed.
    static let mixerUIDPrefix = "Estris.VolumeMixer."

    static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    @discardableResult
    static func read<T>(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
        into value: inout T
    ) -> Bool {
        var address = address(selector, scope: scope, element: element)
        var size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer) == noErr
        }
    }

    @discardableResult
    static func write<T>(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
        _ value: T
    ) -> Bool {
        var address = address(selector, scope: scope, element: element)
        var value = value
        return withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectSetPropertyData(object, &address, 0, nil, UInt32(MemoryLayout<T>.size), pointer) == noErr
        }
    }

    static func isSettable(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> Bool {
        var address = address(selector, scope: scope, element: element)
        guard AudioObjectHasProperty(object, &address) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(object, &address, &settable) == noErr && settable.boolValue
    }

    /// A property holding a list of objects; empty when it can't be read.
    static func objects(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> [AudioObjectID] {
        var address = address(selector, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var list = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &list) == noErr else { return [] }
        return Array(list.prefix(Int(size) / MemoryLayout<AudioObjectID>.size)).filter { $0 != kAudioObjectUnknown }
    }

    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    // MARK: Devices

    static func scope(input: Bool) -> AudioObjectPropertyScope {
        input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput
    }

    /// Every device that plays sound, or every one that records it.
    static func devices(input: Bool) -> [AudioDevice] {
        objects(system, kAudioHardwarePropertyDevices).compactMap { id in
            guard hasStreams(id, input: input),
                  let uid = string(id, kAudioDevicePropertyDeviceUID), !uid.hasPrefix(mixerUIDPrefix)
            else { return nil }
            return AudioDevice(id: id, uid: uid, name: string(id, kAudioObjectPropertyName) ?? uid)
        }
    }

    private static func hasStreams(_ device: AudioObjectID, input: Bool) -> Bool {
        var address = address(kAudioDevicePropertyStreams, scope: scope(input: input))
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
    }

    static func defaultDevice(input: Bool) -> AudioObjectID? {
        var id = AudioObjectID(kAudioObjectUnknown)
        let selector = input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice
        guard read(system, selector, into: &id), id != kAudioObjectUnknown else { return nil }
        return id
    }

    static func setDefaultDevice(_ id: AudioObjectID, input: Bool) {
        let selector = input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice
        write(system, selector, id)
    }

    static func uid(of device: AudioObjectID) -> String? {
        string(device, kAudioDevicePropertyDeviceUID)
    }

    /// The connected device with this UID.
    static func device(uid: String) -> AudioObjectID? {
        var address = address(kAudioHardwarePropertyTranslateUIDToDevice)
        var qualifier = uid as CFString
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafePointer(to: &qualifier) { pointer in
            AudioObjectGetPropertyData(system, &address, UInt32(MemoryLayout<CFString>.size), pointer, &size, &id)
        }
        return status == noErr && id != kAudioObjectUnknown ? id : nil
    }

    // MARK: Volume

    /// The volume as System Settings shows it, between 0 and 1; nil when the device has none
    /// that can be changed (some digital outputs).
    static func volume(of device: AudioObjectID, input: Bool) -> Float? {
        let scope = scope(input: input)
        var value: Float32 = 0
        if isSettable(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: scope),
           read(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: scope, into: &value) {
            return value
        }
        let channels = volumeChannels(of: device, scope: scope)
        guard !channels.isEmpty else { return nil }
        let values = channels.compactMap { channel -> Float32? in
            var value: Float32 = 0
            return read(device, kAudioDevicePropertyVolumeScalar, scope: scope, element: channel, into: &value) ? value : nil
        }
        return values.isEmpty ? nil : values.reduce(0, +) / Float(values.count)
    }

    static func setVolume(_ volume: Float, of device: AudioObjectID, input: Bool) {
        let scope = scope(input: input)
        let value = Float32(min(max(volume, 0), 1))
        if isSettable(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: scope) {
            write(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: scope, value)
            return
        }
        for channel in volumeChannels(of: device, scope: scope) {
            write(device, kAudioDevicePropertyVolumeScalar, scope: scope, element: channel, value)
        }
    }

    /// Whether the device is muted; nil when it can't be muted.
    static func isMuted(_ device: AudioObjectID, input: Bool) -> Bool? {
        let channels = muteChannels(of: device, scope: scope(input: input))
        guard !channels.isEmpty else { return nil }
        // Muted only when every channel is.
        return channels.allSatisfy { channel in
            var value: UInt32 = 0
            return read(device, kAudioDevicePropertyMute, scope: scope(input: input), element: channel, into: &value) && value != 0
        }
    }

    static func setMuted(_ muted: Bool, _ device: AudioObjectID, input: Bool) {
        for channel in muteChannels(of: device, scope: scope(input: input)) {
            write(device, kAudioDevicePropertyMute, scope: scope(input: input), element: channel, UInt32(muted ? 1 : 0))
        }
    }

    private static func muteChannels(of device: AudioObjectID, scope: AudioObjectPropertyScope) -> [AudioObjectPropertyElement] {
        if isSettable(device, kAudioDevicePropertyMute, scope: scope) {
            return [kAudioObjectPropertyElementMain]
        }
        return [1, 2].filter { isSettable(device, kAudioDevicePropertyMute, scope: scope, element: $0) }
    }

    /// Where a device without one main volume keeps it: the whole device, or each channel.
    private static func volumeChannels(of device: AudioObjectID, scope: AudioObjectPropertyScope) -> [AudioObjectPropertyElement] {
        if isSettable(device, kAudioDevicePropertyVolumeScalar, scope: scope) {
            return [kAudioObjectPropertyElementMain]
        }
        return [1, 2].filter { isSettable(device, kAudioDevicePropertyVolumeScalar, scope: scope, element: $0) }
    }
}

/// Calls back on the main queue when an audio property changes, until released.
final class AudioListener {
    private let object: AudioObjectID
    private var address: AudioObjectPropertyAddress
    private let block: AudioObjectPropertyListenerBlock
    /// Whether macOS accepted it; notifications only arrive when it did.
    private(set) var isAdded = false

    init(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        handler: @escaping () -> Void
    ) {
        self.object = object
        address = AudioSystem.address(selector, scope: scope)
        block = { _, _ in handler() }
        isAdded = AudioObjectAddPropertyListenerBlock(object, &address, DispatchQueue.main, block) == noErr
    }

    deinit {
        if isAdded {
            AudioObjectRemovePropertyListenerBlock(object, &address, DispatchQueue.main, block)
        }
    }
}
