import AppKit
import Combine
import SwiftUI

/// The Remap utility: changes what keys and mouse buttons do, per device.
///
/// Key-to-key mappings are set on the keyboard itself (see `KeyMapper`). Everything else,
/// mouse buttons and system actions, goes through an event tap that reads which device each
/// event came from. The same tap feeds the Event Viewer and records keys to remap.
/// Owns everything it needs, so the app only has to create it and call `start()`.
@MainActor
final class Remap {
    let settings = RemapSettings()
    let devices = InputDevices()
    let eventLog = EventLog()
    private let appLog: AppLog
    private lazy var watcher = DeviceWatcher { [weak self] in self?.devicesChanged() }
    private var observers: Set<AnyCancellable> = []
    private var tap: CFMachPort?
    private var lastRefresh = Date.distantPast

    /// Whether the Event Viewer is on screen, so events are logged.
    var isViewing = false {
        didSet { updateTap() }
    }

    /// Whether the pointer is on a Create Mapping button in the Event Viewer.
    var isOverViewerLink = false

    /// Waiting for a key or button on a device, to remap it.
    private var recording: (deviceID: String, done: (RemapInput) -> Void)?

    init(log: AppLog) {
        appLog = log
    }

    func start() {
        devices.refresh()
        watcher.start()
        // Published values arrive before the property changes; applying on the next turn of
        // the run loop reads the new ones.
        settings.$isEnabled.map { _ in () }
            .merge(with: settings.$devices.map { _ in () })
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.apply() }
            .store(in: &observers)
    }

    /// Puts the keyboards back as they were, since their key mappings outlive the app.
    func stop() {
        KeyMapper.clearAll(devices: devices)
    }

    /// The pane shown for this utility in Settings.
    func settingsPane() -> some View {
        RemapPane(remap: self, settings: settings)
    }

    /// Calls `done` with the next key or button pressed on the device, which isn't passed on.
    func record(on deviceID: String, _ done: @escaping (RemapInput) -> Void) {
        recording = (deviceID, done)
        log("recording: waiting for a key or button on \(deviceID)")
        updateTap()
    }

    func cancelRecording() {
        recording = nil
        updateTap()
    }

    private func apply() {
        KeyMapper.apply(settings, devices: devices)
        updateTap()
    }

    private func devicesChanged() {
        devices.refresh()
        lastRefresh = Date()
        apply()
    }

    // MARK: - Event tap

    private func updateTap() {
        let needed = settings.isEnabled || isViewing || recording != nil
        if needed, tap == nil {
            let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp]
            var mask = types.reduce(CGEventMask(0)) { $0 | 1 << $1.rawValue }
            mask |= 1 << Self.systemDefined
            tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: remapTapCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
            guard let tap else { return log("can't watch keys and buttons; needs Accessibility access") }
            CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: needed)
        }
    }

    /// Media and other special keys arrive as this event type, which CGEventType doesn't name.
    private static let systemDefined: UInt32 = 14

    /// Returns false to swallow the event.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return true
        }
        guard let parsed = parse(type: type, event: event) else { return true }

        var device: InputDevice?
        let sender = EventSource.sender(of: event)
        if let sender {
            device = devices.device(sender: sender)
            // A device that just connected, before the watcher noticed.
            if device == nil, Date().timeIntervalSince(lastRefresh) > 2 {
                lastRefresh = Date()
                devices.refresh()
                device = devices.device(sender: sender)
            }
        }

        // A click on Create Mapping in the Event Viewer; logging it would add a row and move
        // the list under the pointer.
        let isLinkClick = isOverViewerLink && (type == .leftMouseDown || type == .leftMouseUp)
        if isViewing, !parsed.isRepeat, !isLinkClick {
            let (original, result) = remapping(of: parsed.input, on: device)
            eventLog.record(InputEvent(
                device: device.map(settings.name(of:)) ?? unknownSource(sender: sender, event: event),
                source: device,
                input: original ?? parsed.input,
                phase: parsed.phase,
                name: original?.title ?? parsed.name,
                detail: parsed.detail,
                result: result?.title
            ))
        }

        if let recording, let input = parsed.input, parsed.phase == .down, input != .mouseButton(0) {
            // Presses whose device is unknown are taken too: some reach macOS without it.
            if let device, device.id != recording.deviceID {
                log("recording: ignored \(parsed.name) from \(device.name), another device")
            } else {
                log("recording: \(parsed.name) from \(device?.name ?? "an unknown device")")
                self.recording = nil
                updateTap()
                recording.done(input)
                return false
            }
        }

        guard settings.isEnabled, let device, let input = parsed.input,
              let output = settings.mappings(for: device.id).first(where: { $0.input == input })?.output
        else { return true }
        // Set on the keyboard itself, so this already is the new key.
        if case .key = input, case .key = output { return true }
        perform(output, down: parsed.phase == .down, isRepeat: parsed.isRepeat)
        return false
    }

    /// For the Event Viewer, when the device isn't known: the app that posted the event (a
    /// mouse or keyboard utility resending it), or the unknown device's ID.
    private func unknownSource(sender: UInt64?, event: CGEvent) -> String {
        if let sender {
            return String(format: "Unknown device 0x%llX", sender)
        }
        let pid = pid_t(event.getIntegerValueField(.eventSourceUnixProcessID))
        guard pid > 0 else { return "Other source" }
        return "Posted by \(NSRunningApplication(processIdentifier: pid)?.localizedName ?? "process \(pid)")"
    }

    /// For the Event Viewer: what an event was remapped to, and, for a key changed on the
    /// keyboard itself (which macOS already reports as the new key), the key pressed.
    private func remapping(of input: RemapInput?, on device: InputDevice?) -> (original: RemapInput?, result: RemapOutput?) {
        guard settings.isEnabled, let device, let input else { return (nil, nil) }
        let mappings = settings.mappings(for: device.id)
        if let output = mappings.first(where: { $0.input == input })?.output {
            return (nil, output)
        }
        if case .key(let usage) = input,
           let mapping = mappings.first(where: { mapping in
               guard case .key? = mapping.input, case .key(usage)? = mapping.output else { return false }
               return true
           }) {
            return (mapping.input, mapping.output)
        }
        return (nil, nil)
    }

    private func perform(_ output: RemapOutput, down: Bool, isRepeat: Bool) {
        switch output {
        case .nothing:
            break
        case .action(let action):
            if down, !isRepeat || action.repeats { action.perform() }
        case .key(let usage):
            guard !isRepeat, let keyCode = KeyCatalog.key(usage: usage)?.keyCode else { return }
            CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: down)?.post(tap: .cghidEventTap)
        case .mouseButton(let number):
            guard !isRepeat, let location = CGEvent(source: nil)?.location else { return }
            let type: CGEventType = switch number {
            case 0: down ? .leftMouseDown : .leftMouseUp
            case 1: down ? .rightMouseDown : .rightMouseUp
            default: down ? .otherMouseDown : .otherMouseUp
            }
            let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: location, mouseButton: CGMouseButton(rawValue: UInt32(number)) ?? .center)
            event?.setIntegerValueField(.mouseEventButtonNumber, value: Int64(number))
            event?.post(tap: .cghidEventTap)
        }
    }

    private struct ParsedEvent {
        /// Nil for events that can't be remapped, such as media keys.
        let input: RemapInput?
        let phase: InputEvent.Phase
        let isRepeat: Bool
        let name: String
        let detail: String
    }

    private func parse(type: CGEventType, event: CGEvent) -> ParsedEvent? {
        switch type {
        case .keyDown, .keyUp, .flagsChanged:
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            var usage = KeyCatalog.key(keyCode: keyCode)?.usage
            if let key = EventSource.key(of: event), key.usage != 0 {
                usage = UInt64(key.usagePage) << 32 | UInt64(key.usage)
            }
            let phase: InputEvent.Phase
            if type == .flagsChanged {
                guard let flag = KeyCatalog.modifierFlag(keyCode: keyCode) else { return nil }
                phase = event.flags.rawValue & flag != 0 ? .down : .up
            } else {
                phase = type == .keyDown ? .down : .up
            }
            var detail = String(format: "key code 0x%02X", keyCode)
            if let usage {
                detail += String(format: ", usage 0x%llX:0x%llX", usage >> 32, usage & 0xFFFF_FFFF)
            }
            return ParsedEvent(
                input: usage.map(RemapInput.key),
                phase: phase,
                isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                name: usage.map(KeyCatalog.name(usage:)) ?? String(format: "Key code 0x%02X", keyCode),
                detail: detail
            )
        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp:
            let number = Int(event.getIntegerValueField(.mouseEventButtonNumber))
            let isDown = type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown
            return ParsedEvent(input: .mouseButton(number), phase: isDown ? .down : .up, isRepeat: false, name: MouseButtons.name(number), detail: "button \(number)")
        default:
            guard type.rawValue == Self.systemDefined, let event = NSEvent(cgEvent: event), event.subtype.rawValue == 8 else { return nil }
            let key = (event.data1 & 0xFFFF_0000) >> 16
            let state = (event.data1 & 0xFF00) >> 8
            return ParsedEvent(input: nil, phase: state == 0xA ? .down : .up, isRepeat: event.data1 & 0x1 != 0, name: SystemAction.mediaKeyName(key), detail: "special key \(key)")
        }
    }

    private func log(_ message: String) {
        appLog.record(message, source: "Remap")
    }
}

/// Plain C function for the event tap; Remap comes back through the refcon. Runs on the main
/// run loop, where the tap is scheduled.
private func remapTapCallback(
    _ proxy: CGEventTapProxy,
    _ type: CGEventType,
    _ event: CGEvent,
    _ refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let remap = Unmanaged<Remap>.fromOpaque(refcon).takeUnretainedValue()
    let passes = MainActor.assumeIsolated { remap.handle(type: type, event: event) }
    return passes ? Unmanaged.passUnretained(event) : nil
}
