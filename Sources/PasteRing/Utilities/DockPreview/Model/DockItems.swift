import AppKit
import ApplicationServices

/// Where the Dock sits, from its own preferences.
struct DockLayout {
    enum Edge: String {
        case bottom, left, right
    }

    let edge: Edge
    /// How far from that edge of the screen its icons reach, in points, magnified included.
    let reach: CGFloat

    /// Read again each time: the user can move or resize the Dock at any moment.
    static func current() -> DockLayout {
        let defaults = UserDefaults(suiteName: "com.apple.dock")
        let edge = Edge(rawValue: defaults?.string(forKey: "orientation") ?? "") ?? .bottom
        let tile = CGFloat(defaults?.double(forKey: "tilesize") ?? 0)
        let large = defaults?.bool(forKey: "magnification") == true ? CGFloat(defaults?.double(forKey: "largesize") ?? 0) : 0
        // Room for the icon, the gap around it and the running-app dot.
        return DockLayout(edge: edge, reach: max(tile > 0 ? tile : 48, large) + 24)
    }

    /// Whether a point (AppKit coordinates) is close enough to the Dock's edge to be over it,
    /// so Accessibility is only asked there.
    func isNear(_ point: NSPoint) -> Bool {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) else { return false }
        switch edge {
        case .bottom: return point.y <= screen.frame.minY + reach
        case .left: return point.x <= screen.frame.minX + reach
        case .right: return point.x >= screen.frame.maxX - reach
        }
    }
}

/// A running app's icon in the Dock.
struct DockItem: Equatable {
    let app: NSRunningApplication
    /// In AppKit coordinates.
    let frame: NSRect
}

/// Finds the Dock icon under the pointer through Accessibility.
enum DockItems {
    /// The running app whose Dock icon is at a point (AppKit coordinates); nil over anything
    /// else, including apps that aren't running.
    static func item(at point: NSPoint) -> DockItem? {
        guard let dockPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
        else { return nil }
        let axPoint = AXWindow.axPoint(point)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(axPoint.x), Float(axPoint.y), &hit) == .success,
              var element = hit
        else { return nil }
        AXUIElementSetMessagingTimeout(element, 0.2)
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid == dockPID else { return nil }

        // The icon itself, or a part of it.
        for _ in 0..<4 {
            if string(element, kAXSubroleAttribute) == "AXApplicationDockItem" {
                guard let app = runningApp(for: element), let frame = frame(of: element) else { return nil }
                return DockItem(app: app, frame: frame)
            }
            guard let parent = AXUI.element(element, kAXParentAttribute) else { return nil }
            element = parent
        }
        return nil
    }

    /// Whether one of the Dock's menus is on screen (its icons' right-click menu).
    static func isMenuOpen() -> Bool {
        guard let dockPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        let menuLayer = Int(CGWindowLevelForKey(.popUpMenuWindow))
        return list.contains { $0[kCGWindowOwnerPID as String] as? pid_t == dockPID && $0[kCGWindowLayer as String] as? Int == menuLayer }
    }

    private static func runningApp(for element: AXUIElement) -> NSRunningApplication? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXURLAttribute as CFString, &value) == .success,
              let url = value as? URL
        else { return nil }
        let path = url.standardizedFileURL.path
        return NSWorkspace.shared.runningApplications.first { app in
            app.activationPolicy == .regular && !app.isTerminated && app.bundleURL?.standardizedFileURL.path == path
        }
    }

    private static func frame(of element: AXUIElement) -> NSRect? {
        guard let position = AXUI.point(element, kAXPositionAttribute), let size = AXUI.size(element, kAXSizeAttribute) else { return nil }
        return AXWindow.appKitRect(CGRect(origin: position, size: size))
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        AXUI.string(element, attribute)
    }
}

/// Small helpers to read Accessibility attributes.
enum AXUI {
    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? Bool
    }

    static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }

    static func size(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
    }
}
