import AppKit
import ApplicationServices

/// A window to snap: another app's, moved and resized through the Accessibility API, or one
/// of PasteRing's own, moved directly.
///
/// Accessibility frames are in global coordinates with the origin at the top left of the
/// main screen and y growing down; AppKit's are from the bottom left with y growing up.
/// `frame` and `setFrame` use AppKit's, like `NSScreen`.
struct AXWindow {
    /// Longest any single request may block, so a busy app can't freeze dragging.
    private static let messagingTimeout: Float = 0.25

    let element: AXUIElement?
    /// One of PasteRing's own windows.
    let own: NSWindow?
    let pid: pid_t

    init(element: AXUIElement) {
        self.element = element
        own = nil
        AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        self.pid = pid
    }

    init(own window: NSWindow) {
        element = nil
        own = window
        pid = getpid()
    }

    /// PasteRing's own window under a point, leaving out panels such as the snap preview.
    private static func ownWindow(at point: NSPoint) -> NSWindow? {
        NSApp.windows.first { window in
            window.isVisible && !(window is NSPanel) && window.styleMask.contains(.titled) && window.frame.contains(point)
        }
    }

    /// The front app's focused window.
    static func focused() -> AXWindow? {
        if NSApp.isActive, let window = NSApp.keyWindow, !(window is NSPanel) {
            return AXWindow(own: window)
        }
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, messagingTimeout)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return AXWindow(element: value as! AXUIElement)
    }

    /// The window under a point given in AppKit coordinates.
    static func at(_ point: NSPoint) -> AXWindow? {
        // Ours are frontmost only if the pointer is over one and it is above other apps'.
        if let window = ownWindow(at: point), window.windowNumber == NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0) {
            return AXWindow(own: window)
        }
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, messagingTimeout)
        let ax = axPoint(point)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(ax.x), Float(ax.y), &hit) == .success, let hit else { return nil }
        if role(of: hit) == kAXWindowRole as String { return AXWindow(element: hit) }
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(hit, kAXWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID()
        else { return nil }
        return AXWindow(element: window as! AXUIElement)
    }

    /// An app's window whose frame matches, for windows found through the window server.
    static func of(pid: pid_t, matching frame: NSRect) -> AXWindow? {
        if pid == getpid() {
            return NSApp.windows.first { $0.isVisible && $0.frame.equalTo(frame) }.map(AXWindow.init(own:))
        }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, messagingTimeout)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement]
        else { return nil }
        return windows.lazy.map(AXWindow.init(element:)).first { window in
            guard let candidate = window.frame else { return false }
            return abs(candidate.minX - frame.minX) < 2 && abs(candidate.minY - frame.minY) < 2
                && abs(candidate.width - frame.width) < 2 && abs(candidate.height - frame.height) < 2
        }
    }

    var frame: NSRect? {
        if let own { return own.frame }
        guard let element else { return nil }
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue
        else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return Self.appKitRect(CGRect(origin: position, size: size))
    }

    func setFrame(_ frame: NSRect) {
        if let own {
            own.setFrame(frame, display: true)
            return
        }
        guard let element else { return }
        let rect = Self.axRect(frame)
        var position = rect.origin
        var size = rect.size
        guard let positionValue = AXValueCreate(.cgPoint, &position), let sizeValue = AXValueCreate(.cgSize, &size) else { return }
        // Size, position, then size again: a window can't grow past a screen edge, so the
        // first size may be cut short until it has moved.
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, positionValue)
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
    }

    func isSame(as other: AXWindow) -> Bool {
        if let own, let otherOwn = other.own { return own === otherOwn }
        guard let element, let otherElement = other.element else { return false }
        return CFEqual(element, otherElement)
    }

    /// The screen showing most of the window.
    var screen: NSScreen? {
        guard let frame else { return NSScreen.main }
        return NSScreen.screens.max { area($0.frame.intersection(frame)) < area($1.frame.intersection(frame)) }
    }

    private func area(_ rect: NSRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }

    private static func role(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value)
        return value as? String
    }

    // MARK: - Coordinates

    private static var mainScreenHeight: CGFloat {
        NSScreen.screens.first?.frame.maxY ?? 0
    }

    static func axPoint(_ point: NSPoint) -> CGPoint {
        CGPoint(x: point.x, y: mainScreenHeight - point.y)
    }

    static func axRect(_ rect: NSRect) -> CGRect {
        CGRect(x: rect.minX, y: mainScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func appKitRect(_ rect: CGRect) -> NSRect {
        NSRect(x: rect.minX, y: mainScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
