import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine
import SwiftUI

/// The Delete to Trash utility: in Finder, Delete (and Forward Delete) on its own moves the
/// selected files and folders to the Trash, as ⌘⌫ does. Left alone while typing (renaming a
/// file, the search field), with a modifier held, and in every other app. Owns everything it
/// needs, so the app only has to create it and call `start()`.
@MainActor
final class DeleteToTrash {
    private static let finder = "com.apple.finder"
    /// Accessibility calls into a busy Finder give up after this long instead of stalling keys.
    private static let messagingTimeout: Float = 0.2
    /// Roles of elements that take text: there, the key deletes text.
    private static let textRoles: Set<String> = [
        kAXTextFieldRole as String, kAXTextAreaRole as String, kAXComboBoxRole as String, "AXSearchField",
    ]

    let settings = DeleteToTrashSettings()
    private let appLog: AppLog
    private var observers: Set<AnyCancellable> = []
    private var tap: CFMachPort?

    init(log: AppLog) {
        appLog = log
    }

    func start() {
        settings.$isEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in self?.setActive(enabled) }
            .store(in: &observers)
    }

    /// The pane shown for this utility in Settings.
    func settingsPane() -> some View {
        DeleteToTrashPane(settings: settings)
    }

    private func setActive(_ active: Bool) {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: active)
            return
        }
        guard active else { return }
        tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: deleteToTrashCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        guard let tap else { return log("can't watch the Delete key; needs Accessibility access") }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
    }

    /// Turns a plain Delete in Finder into ⌘⌫, changing the event in place. Returns false to
    /// swallow it.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .keyDown:
            break
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap, settings.isEnabled { CGEvent.tapEnable(tap: tap, enable: true) }
            return true
        default:
            return true
        }
        let key = Int(event.getIntegerValueField(.keyboardEventKeycode))
        guard key == kVK_Delete || (key == kVK_ForwardDelete && settings.usesForwardDelete),
              // fn comes with Forward Delete on a laptop keyboard; any other modifier is a shortcut.
              event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty,
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.finder,
              !isTyping()
        else { return true }
        // Holding the key would send the files to the Trash one after another: one press, once.
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return false }
        event.setIntegerValueField(.keyboardEventKeycode, value: Int64(kVK_Delete))
        event.flags = event.flags.subtracting(.maskSecondaryFn).union(.maskCommand)
        log("moved the selection to the Trash")
        return true
    }

    /// Whether the focus is on something that takes text, or it can't be told: then the key
    /// is left as it is.
    private func isTyping() -> Bool {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, Self.messagingTimeout)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return true }
        let focused = value as! AXUIElement
        AXUIElementSetMessagingTimeout(focused, Self.messagingTimeout)
        for attribute in [kAXRoleAttribute, kAXSubroleAttribute] {
            var text: CFTypeRef?
            if AXUIElementCopyAttributeValue(focused, attribute as CFString, &text) == .success,
               let text = text as? String, Self.textRoles.contains(text) {
                return true
            }
        }
        return false
    }

    private func log(_ message: String) {
        appLog.record(message, source: "Delete to Trash")
    }
}

/// Plain C function for the event tap; the utility comes back through the refcon. Runs on the
/// main run loop, where the tap is scheduled.
private func deleteToTrashCallback(
    _ proxy: CGEventTapProxy,
    _ type: CGEventType,
    _ event: CGEvent,
    _ refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let utility = Unmanaged<DeleteToTrash>.fromOpaque(refcon).takeUnretainedValue()
    let passes = MainActor.assumeIsolated { utility.handle(type: type, event: event) }
    return passes ? Unmanaged.passUnretained(event) : nil
}
