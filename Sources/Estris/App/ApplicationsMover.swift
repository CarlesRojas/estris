import AppKit

/// Opened from the disk image or Downloads, Estris offers to move itself to Applications,
/// where it stays installed and can open at login. It then opens again from there and ejects
/// the disk image, closing its window.
@MainActor
enum ApplicationsMover {
    private static let destination = URL(fileURLWithPath: "/Applications/Estris.app")

    /// Where the app really is: macOS runs a downloaded app from a random read-only copy
    /// (App Translocation) until it is moved, so the bundle path alone doesn't say.
    static var originalURL: URL {
        originalPath(of: Bundle.main.bundleURL) ?? Bundle.main.bundleURL
    }

    /// Run from a mounted disk image or the Downloads folder: places it isn't meant to stay.
    static var isOutsideApplications: Bool {
        let path = originalURL.path
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? "~/Downloads"
        return path.hasPrefix("/Volumes/") || path.hasPrefix(downloads + "/")
    }

    /// Asks, when outside Applications, and moves the app. Returns true when it is moving and
    /// opening again, so the rest of the launch should stop.
    static func offerIfNeeded() -> Bool {
        guard isOutsideApplications else { return false }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = String(localized: "Move Estris to Applications?")
        alert.informativeText = String(localized: "It is running from where it was downloaded. In Applications it stays installed and can open at login.")
        alert.addButton(withTitle: String(localized: "Move to Applications"))
        alert.addButton(withTitle: String(localized: "Not Now"))
        guard alert.runModal() == .alertFirstButtonReturn else { return false }

        do {
            try move()
        } catch {
            let failure = NSAlert()
            failure.messageText = String(localized: "Couldn't move Estris to Applications")
            failure.informativeText = String(localized: "Drag it to the Applications folder yourself, then open it from there.")
            failure.runModal()
            return false
        }
        relaunchFromApplications()
        return true
    }

    private static func move() throws {
        let manager = FileManager.default
        if manager.fileExists(atPath: destination.path) {
            try manager.trashItem(at: destination, resultingItemURL: nil)
        }
        try manager.copyItem(at: Bundle.main.bundleURL, to: destination)
        // Already checked by macOS when it opened from the download; not asked again.
        let xattr = Process()
        xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattr.arguments = ["-dr", "com.apple.quarantine", destination.path]
        try? xattr.run()
        xattr.waitUntilExit()
    }

    /// Opens the moved copy once this one has quit, then ejects the disk image it came from.
    private static func relaunchFromApplications() {
        let path = originalURL.path
        var volume = ""
        if path.hasPrefix("/Volumes/") {
            let parts = path.split(separator: "/", omittingEmptySubsequences: true)
            if parts.count >= 2 { volume = "/" + parts[0...1].joined(separator: "/") }
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; open \"$0\"; [ -n \"$1\" ] && hdiutil detach \"$1\" -quiet", destination.path, volume]
        try? process.run()
        NSApp.terminate(nil)
    }

    /// The original location of a translocated app, through Security's own function for it
    /// (`SecTranslocateCreateOriginalPathForURL`), looked up at run time as it isn't public.
    private static func originalPath(of url: URL) -> URL? {
        typealias IsTranslocated = @convention(c) (CFURL, UnsafeMutablePointer<DarwinBoolean>, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> DarwinBoolean
        typealias OriginalPath = @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?
        guard let security = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY),
              let isSymbol = dlsym(security, "SecTranslocateIsTranslocatedURL"),
              let originalSymbol = dlsym(security, "SecTranslocateCreateOriginalPathForURL")
        else { return nil }
        var translocated: DarwinBoolean = false
        guard unsafeBitCast(isSymbol, to: IsTranslocated.self)(url as CFURL, &translocated, nil).boolValue,
              translocated.boolValue,
              let original = unsafeBitCast(originalSymbol, to: OriginalPath.self)(url as CFURL, nil)
        else { return nil }
        return original.takeRetainedValue() as URL
    }
}
