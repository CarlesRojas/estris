import AppKit

/// Things a remapped key or button can do besides typing a key.
enum SystemAction: String, CaseIterable, Codable {
    case missionControl
    case appWindows
    case showDesktop
    case launchpad
    case nextDesktop
    case previousDesktop
    case volumeUp
    case volumeDown
    case mute
    case playPause
    case nextTrack
    case previousTrack
    case brightnessUp
    case brightnessDown
    case keyboardBrightnessUp
    case keyboardBrightnessDown
    case sleepDisplay
    case lockScreen
    case spotlight
    case screenshot
    case screenshotSelection
    case screenshotScreen
    case emojiPicker
    case forceQuit

    enum Section: String, CaseIterable {
        case desktops = "Mission Control and Desktops"
        case media = "Media"
        case display = "Display and Keyboard"
        case system = "System"

        var title: String { localized(rawValue) }
    }

    var section: Section {
        switch self {
        case .missionControl, .appWindows, .showDesktop, .launchpad, .nextDesktop, .previousDesktop: .desktops
        case .volumeUp, .volumeDown, .mute, .playPause, .nextTrack, .previousTrack: .media
        case .brightnessUp, .brightnessDown, .keyboardBrightnessUp, .keyboardBrightnessDown, .sleepDisplay: .display
        case .lockScreen, .spotlight, .screenshot, .screenshotSelection, .screenshotScreen, .emojiPicker, .forceQuit: .system
        }
    }

    var title: String {
        switch self {
        case .missionControl: String(localized: "Mission Control")
        case .appWindows: String(localized: "App Windows")
        case .showDesktop: String(localized: "Show Desktop")
        case .launchpad: String(localized: "Launchpad")
        case .nextDesktop: String(localized: "Next Desktop")
        case .previousDesktop: String(localized: "Previous Desktop")
        case .volumeUp: String(localized: "Volume Up")
        case .volumeDown: String(localized: "Volume Down")
        case .mute: String(localized: "Mute")
        case .playPause: String(localized: "Play or Pause")
        case .nextTrack: String(localized: "Next Track")
        case .previousTrack: String(localized: "Previous Track")
        case .brightnessUp: String(localized: "Brightness Up")
        case .brightnessDown: String(localized: "Brightness Down")
        case .keyboardBrightnessUp: String(localized: "Keyboard Brightness Up")
        case .keyboardBrightnessDown: String(localized: "Keyboard Brightness Down")
        case .sleepDisplay: String(localized: "Sleep Display")
        case .lockScreen: String(localized: "Lock Screen")
        case .spotlight: String(localized: "Spotlight")
        case .screenshot: String(localized: "Screenshot Tools")
        case .screenshotSelection: String(localized: "Screenshot of Selection")
        case .screenshotScreen: String(localized: "Screenshot of Screen")
        case .emojiPicker: String(localized: "Emoji and Symbols")
        case .forceQuit: String(localized: "Force Quit Applications")
        }
    }

    /// Whether holding the key repeats it, like the real volume and brightness keys.
    var repeats: Bool {
        switch self {
        case .volumeUp, .volumeDown, .brightnessUp, .brightnessDown, .keyboardBrightnessUp, .keyboardBrightnessDown: true
        default: false
        }
    }

    func perform() {
        switch self {
        case .missionControl: Self.dock("com.apple.expose.awake")
        case .appWindows: Self.dock("com.apple.expose.front.awake")
        case .showDesktop: Self.dock("com.apple.showdesktop.awake")
        case .launchpad: Self.dock("com.apple.launchpad.toggle")
        // The system shortcuts for moving between desktops (on by default).
        case .nextDesktop: Self.press(0x7C, [.maskControl, .maskSecondaryFn, .maskNumericPad])
        case .previousDesktop: Self.press(0x7B, [.maskControl, .maskSecondaryFn, .maskNumericPad])
        case .volumeUp: Self.mediaKey(0)
        case .volumeDown: Self.mediaKey(1)
        case .mute: Self.mediaKey(7)
        case .playPause: Self.mediaKey(16)
        case .nextTrack: Self.mediaKey(17)
        case .previousTrack: Self.mediaKey(18)
        case .brightnessUp: Self.mediaKey(2)
        case .brightnessDown: Self.mediaKey(3)
        case .keyboardBrightnessUp: Self.mediaKey(21)
        case .keyboardBrightnessDown: Self.mediaKey(22)
        case .sleepDisplay:
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            process.arguments = ["displaysleepnow"]
            try? process.run()
        case .lockScreen: Self.press(0x0C, [.maskControl, .maskCommand])
        case .spotlight: Self.press(0x31, [.maskCommand])
        case .screenshot: Self.press(0x17, [.maskCommand, .maskShift])
        case .screenshotSelection: Self.press(0x15, [.maskCommand, .maskShift])
        case .screenshotScreen: Self.press(0x14, [.maskCommand, .maskShift])
        case .emojiPicker: Self.press(0x31, [.maskControl, .maskCommand])
        case .forceQuit: Self.press(0x35, [.maskCommand, .maskAlternate])
        }
    }

    /// Presses and releases a key with modifiers held.
    static func press(_ keyCode: CGKeyCode, _ flags: CGEventFlags) {
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }

    /// Presses one of the special keys on Apple keyboards (volume, brightness, media).
    private static func mediaKey(_ key: Int) {
        for down in [true, false] {
            let state = down ? 0xA : 0xB
            NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: key << 16 | state << 8,
                data2: -1
            )?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    /// Asks the Dock for Mission Control and its relatives, through a private call looked up
    /// at run time.
    private static func dock(_ notification: String) {
        typealias SendNotification = @convention(c) (CFString, UnsafeMutableRawPointer?) -> Void
        guard let symbol = dlsym(dlopen(nil, RTLD_NOW), "CoreDockSendNotification") else { return }
        unsafeBitCast(symbol, to: SendNotification.self)(notification as CFString, nil)
    }

    /// Names for the special keys, by the number macOS gives them, for the Event Viewer.
    static func mediaKeyName(_ key: Int) -> String {
        switch key {
        case 0: String(localized: "Volume Up")
        case 1: String(localized: "Volume Down")
        case 2: String(localized: "Brightness Up")
        case 3: String(localized: "Brightness Down")
        case 7: String(localized: "Mute")
        case 14: String(localized: "Eject")
        case 16: String(localized: "Play or Pause")
        case 17: String(localized: "Next Track")
        case 18: String(localized: "Previous Track")
        case 19: String(localized: "Fast Forward")
        case 20: String(localized: "Rewind")
        case 21: String(localized: "Keyboard Brightness Up")
        case 22: String(localized: "Keyboard Brightness Down")
        case 23: String(localized: "Keyboard Backlight Toggle")
        default: String(localized: "Special Key \(key)")
        }
    }
}
