import AppKit
import ApplicationServices
import ScreenCaptureKit

/// One of an app's windows, as the window server lists it.
struct AppWindow: Identifiable, Equatable {
    let id: CGWindowID
    let title: String
    /// Width over height, for the preview's shape.
    let aspect: CGFloat
}

/// Lists an app's windows, captures their thumbnails, and brings one forward or closes it.
@available(macOS 14, *)
enum AppWindows {
    /// At most this many previews, so the panel fits on screen.
    static let limit = 10

    /// Front to back. With `currentDesktopOnly`, only the windows on screen now; otherwise those
    /// on other desktops too, and minimized ones (which have a title, unlike helper windows).
    static func windows(of pid: pid_t, currentDesktopOnly: Bool) -> [AppWindow] {
        let options: CGWindowListOption = currentDesktopOnly
            ? [.optionOnScreenOnly, .excludeDesktopElements]
            : [.optionAll, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        let windows = list.compactMap { entry -> AppWindow? in
            guard entry[kCGWindowOwnerPID as String] as? pid_t == pid,
                  entry[kCGWindowLayer as String] as? Int == 0,
                  let number = entry[kCGWindowNumber as String] as? Int,
                  let boundsInfo = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary),
                  bounds.width >= 100, bounds.height >= 60,
                  (entry[kCGWindowAlpha as String] as? Double ?? 1) > 0
            else { return nil }
            let title = entry[kCGWindowName as String] as? String ?? ""
            let isOnScreen = entry[kCGWindowIsOnscreen as String] as? Bool ?? false
            guard isOnScreen || !title.isEmpty else { return nil }
            return AppWindow(id: CGWindowID(number), title: title, aspect: bounds.width / bounds.height)
        }
        return Array(windows.prefix(limit))
    }

    /// Thumbnails, at most `maxPixels` on their longer side, handed over one by one as they're
    /// ready. Asks for Screen Recording the first time; without it, none arrive.
    static func captureThumbnails(of windows: [AppWindow], maxPixels: CGFloat, onImage: @escaping @MainActor (CGWindowID, CGImage) -> Void) -> Task<Void, Never> {
        Task {
            guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) else { return }
            for window in windows {
                guard !Task.isCancelled else { return }
                guard let scWindow = content.windows.first(where: { $0.windowID == window.id }) else { continue }
                let frame = scWindow.frame
                let scale = min(1, maxPixels / max(frame.width, frame.height, 1))
                let configuration = SCStreamConfiguration()
                configuration.width = max(1, Int((frame.width * scale).rounded()))
                configuration.height = max(1, Int((frame.height * scale).rounded()))
                configuration.showsCursor = false
                let filter = SCContentFilter(desktopIndependentWindow: scWindow)
                guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) else { continue }
                await onImage(window.id, image)
            }
        }
    }

    /// Brings the window to the front (un-minimizing it) and activates its app. A window on
    /// another desktop: the app is activated and macOS switches there.
    static func open(_ window: AppWindow, of app: NSRunningApplication) {
        if let element = element(for: window.id, pid: app.processIdentifier) {
            AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        }
        app.activate()
    }

    /// Presses the window's close button, as clicking it would.
    static func close(_ window: AppWindow, of app: NSRunningApplication) {
        guard let element = element(for: window.id, pid: app.processIdentifier),
              let button = AXUI.element(element, kAXCloseButtonAttribute)
        else { return }
        AXUIElementPerformAction(button, kAXPressAction as CFString)
    }

    /// Whether the window can be closed from here: Accessibility only reaches windows on the
    /// desktop in use and minimized ones.
    static func canClose(_ window: AppWindow, of pid: pid_t) -> Bool {
        element(for: window.id, pid: pid).flatMap { AXUI.element($0, kAXCloseButtonAttribute) } != nil
    }

    /// The Accessibility window for a window server window, matched by its number.
    private static func element(for id: CGWindowID, pid: pid_t) -> AXUIElement? {
        guard let windowNumber else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        return AXUI.elements(app, kAXWindowsAttribute).first { element in
            var number: CGWindowID = 0
            return windowNumber(element, &number) == .success && number == id
        }
    }

    /// `_AXUIElementGetWindow`, which every window manager uses to pair the two; looked up at
    /// run time, so a macOS without it only loses closing and raising a specific window.
    private static let windowNumber: (@convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError)? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError).self)
    }()
}
