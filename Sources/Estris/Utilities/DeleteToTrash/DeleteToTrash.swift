import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine
import SwiftUI

/// The Delete to Trash utility: Delete deletes what is selected, as on Windows. In any app with
/// a menu command on ⌘⌫ (Move to Trash in Finder, Delete in Photos, Notes, Music…), Delete on
/// its own is sent on as ⌘⌫; with Shift, as ⌥⌘⌫ where the app has that (Delete Immediately).
/// Left alone while typing, with another modifier held, in excluded apps and in apps without
/// such a command. Owns everything it needs, so the app only has to create it and call
/// `start()`.
@MainActor
final class DeleteToTrash {
    private static let finder = "com.apple.finder"
    /// Accessibility calls into a busy app give up after this long instead of stalling keys.
    private static let messagingTimeout: Float = 0.2
    /// How long an app's menu commands are trusted before they are read again.
    private static let commandsLifetime: TimeInterval = 5
    /// Roles of elements that take text: there, the key deletes text.
    private static let textRoles: Set<String> = [
        kAXTextFieldRole as String, kAXTextAreaRole as String, kAXComboBoxRole as String, "AXSearchField",
    ]

    let settings = DeleteToTrashSettings()
    private let appLog: AppLog
    private var observers: Set<AnyCancellable> = []
    private var tap: CFMachPort?
    private var activationObserver: NSObjectProtocol?
    /// Each app's delete commands, and when they were read.
    private var knownCommands: [pid_t: (found: Set<DeleteCommand>, time: Date)] = [:]

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
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        activationObserver = nil
        knownCommands = [:]
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: active)
        }
        guard active else { return }
        if tap == nil {
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
        // Reads the menus of the app switched to ahead, so the first press doesn't wait for them.
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            MainActor.assumeIsolated { self?.readCommandsAhead(of: pid) }
        }
    }

    /// Sends a plain Delete on as the app's delete command, changing the event in place.
    /// Returns false to swallow it.
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
        guard (key == kVK_Delete && settings.usesDelete) || (key == kVK_ForwardDelete && settings.usesForwardDelete),
              // fn comes with Forward Delete on a Mac keyboard; ⌘, ⌃ and ⌥ make it a shortcut.
              event.flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty,
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              !settings.excludedApps.contains(app.bundleIdentifier ?? "")
        else { return true }
        let withShift = event.flags.contains(.maskShift)
        if withShift, !settings.shiftDeletesImmediately { return true }
        guard !isTyping() else { return true }

        // Finder keeps Delete Immediately as a hidden alternate of Move to Trash, which menus
        // may not show to Accessibility; it always has both.
        let found: Set<DeleteCommand> = app.bundleIdentifier == Self.finder ? [.trash, .immediately] : commands(of: app.processIdentifier)
        var command: DeleteCommand = withShift ? .immediately : .trash
        // In Finder's Trash, ⌘⌫ puts things back: there Delete deletes them, as on Windows.
        if app.bundleIdentifier == Self.finder, Self.isFinderTrashInFront(app.processIdentifier) {
            command = .immediately
        }
        guard found.contains(command) else { return true }
        // Holding the key would delete one thing after another: one press, once.
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return false }
        event.setIntegerValueField(.keyboardEventKeycode, value: Int64(kVK_Delete))
        event.flags = event.flags.subtracting([.maskSecondaryFn, .maskShift]).union(command.flags)
        log("\(command == .trash ? "⌘⌫" : "⌥⌘⌫") in \(app.localizedName ?? "\(app.processIdentifier)")")
        return true
    }

    // MARK: Accessibility

    /// Whether the focus is on something that takes text, or it can't be told: then the key
    /// is left as it is.
    private func isTyping() -> Bool {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, Self.messagingTimeout)
        guard let focused = Self.element(system, kAXFocusedUIElementAttribute) else { return true }
        AXUIElementSetMessagingTimeout(focused, Self.messagingTimeout)
        return [kAXRoleAttribute, kAXSubroleAttribute].contains { attribute in
            Self.value(focused, attribute).map { Self.textRoles.contains($0 as? String ?? "") } ?? false
        }
    }

    private func commands(of pid: pid_t) -> Set<DeleteCommand> {
        if let known = knownCommands[pid], Date().timeIntervalSince(known.time) < Self.commandsLifetime {
            return known.found
        }
        let found = Self.readCommands(of: pid)
        knownCommands[pid] = (found, Date())
        return found
    }

    private func readCommandsAhead(of pid: pid_t) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let found = Self.readCommands(of: pid)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.knownCommands[pid] = (found, Date()) }
            }
        }
    }

    /// The delete commands in an app's menu bar, from the items of each menu (submenus are
    /// left out, to stay quick). Matched by shortcut, so it doesn't matter what they're called
    /// or in which language.
    nonisolated private static func readCommands(of pid: pid_t) -> Set<DeleteCommand> {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        guard let menuBar = element(app, kAXMenuBarAttribute) else { return [] }
        var found: Set<DeleteCommand> = []
        for menuBarItem in children(menuBar) {
            for menu in children(menuBarItem) {
                for item in children(menu) {
                    if let command = DeleteCommand(item: item) { found.insert(command) }
                }
            }
        }
        return found
    }

    /// Whether Finder's window in front shows the Trash, by its title.
    private static func isFinderTrashInFront(_ pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        guard let trash = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first,
              let window = element(app, kAXFocusedWindowAttribute),
              let title = value(window, kAXTitleAttribute) as? String
        else { return false }
        return title == FileManager.default.displayName(atPath: trash.path)
    }

    nonisolated fileprivate static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    nonisolated private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = value(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    nonisolated private static func children(_ element: AXUIElement) -> [AXUIElement] {
        value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    private func log(_ message: String) {
        appLog.record(message, source: "Delete to Trash")
    }
}

/// What Delete is sent on as.
private enum DeleteCommand {
    /// ⌘⌫: Move to Trash, Delete.
    case trash
    /// ⌥⌘⌫: Delete Immediately.
    case immediately

    var flags: CGEventFlags {
        switch self {
        case .trash: .maskCommand
        case .immediately: [.maskCommand, .maskAlternate]
        }
    }

    /// The command a menu item's shortcut is, if it is one of these.
    init?(item: AXUIElement) {
        typealias Utility = DeleteToTrash
        let key = Utility.value(item, kAXMenuItemCmdVirtualKeyAttribute) as? Int
        let glyph = Utility.value(item, kAXMenuItemCmdGlyphAttribute) as? Int
        let character = Utility.value(item, kAXMenuItemCmdCharAttribute) as? String
        // The Delete key, however the app gives it: its key code, its ⌫ glyph or its character.
        guard key == kVK_Delete || glyph == kMenuDeleteLeftGlyph || character == "\u{8}" || character == "\u{7F}" else { return nil }
        // 0 is ⌘ alone; 2 adds ⌥. Anything else (Shift, ⌃, no ⌘) isn't one of these.
        switch Utility.value(item, kAXMenuItemCmdModifiersAttribute) as? Int ?? 0 {
        case 0: self = .trash
        case 2: self = .immediately
        default: return nil
        }
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
