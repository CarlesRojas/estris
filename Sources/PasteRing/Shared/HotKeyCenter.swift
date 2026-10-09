import Foundation
import Carbon.HIToolbox

/// Global hotkeys via Carbon's RegisterEventHotKey, which needs no special permissions.
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private struct Definition {
        let keyCode: UInt32
        let modifiers: UInt32
        let handler: () -> Void
    }

    private let signature: OSType = 0x5052_4E47 // "PRNG"
    private var definitions: [UInt32: Definition] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?
    /// While suspended, hotkeys stay defined but are not registered, so key presses reach
    /// the app normally (for example while recording a new shortcut).
    private var isSuspended = false

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr else { return status }
            HotKeyCenter.shared.definitions[hotKeyID.id]?.handler()
            return noErr
        }, 1, &spec, nil, &eventHandler)
    }

    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) -> UInt32 {
        let id = nextID
        nextID += 1
        definitions[id] = Definition(keyCode: keyCode, modifiers: modifiers, handler: handler)
        if !isSuspended {
            activate(id)
        }
        return id
    }

    func unregister(_ id: UInt32) {
        deactivate(id)
        definitions.removeValue(forKey: id)
    }

    func suspend() {
        guard !isSuspended else { return }
        isSuspended = true
        definitions.keys.forEach(deactivate)
    }

    func resume() {
        guard isSuspended else { return }
        isSuspended = false
        definitions.keys.forEach(activate)
    }

    private func activate(_ id: UInt32) {
        guard let definition = definitions[id], refs[id] == nil else { return }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            definition.keyCode,
            definition.modifiers,
            EventHotKeyID(signature: signature, id: id),
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr, let ref {
            refs[id] = ref
        } else {
            NSLog("PasteRing: failed to register hotkey \(definition.keyCode) (status \(status))")
        }
    }

    private func deactivate(_ id: UInt32) {
        if let ref = refs.removeValue(forKey: id) {
            UnregisterEventHotKey(ref)
        }
    }
}
