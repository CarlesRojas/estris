import AppKit
import SwiftUI

/// Looks up and caches app icons and names by bundle identifier.
@MainActor
enum AppIcons {
    private static var icons: [String: NSImage] = [:]
    private static var names: [String: String] = [:]

    /// Icons are cached as small bitmaps: the full icon holds sizes up to 1024 px, and
    /// drawing that in every list row makes scrolling stutter.
    static func icon(for bundleID: String?, at url: URL? = nil) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = icons[bundleID] { return cached }
        guard let url = url ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let image = downscaled(NSWorkspace.shared.icon(forFile: url.path), side: 64)
        icons[bundleID] = image
        return image
    }

    private static func downscaled(_ image: NSImage, side: Int) -> NSImage {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else { return image }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        let small = NSImage(size: NSSize(width: side / 2, height: side / 2))
        small.addRepresentation(bitmap)
        return small
    }

    static func name(for bundleID: String?) -> String? {
        guard let bundleID else { return nil }
        if let cached = names[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        names[bundleID] = name
        return name
    }
}

/// Icon of the app an entry was copied from, or a generic clipboard symbol.
struct AppIconView: View {
    let bundleID: String?
    let size: CGFloat
    /// Where the app is, when already known; saves a Launch Services lookup.
    var url: URL?

    var body: some View {
        Group {
            if let image = AppIcons.icon(for: bundleID, at: url) {
                Image(nsImage: image)
                    .resizable()
            } else {
                Image(systemName: "doc.on.clipboard")
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.18)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}
