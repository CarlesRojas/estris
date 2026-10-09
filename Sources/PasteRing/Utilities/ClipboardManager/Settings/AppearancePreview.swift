import AppKit
import SwiftUI

/// Overlay elements at real size over the desktop wallpaper, drawn with the current settings.
struct AppearancePreview: View {
    @ObservedObject var appearance: AppearanceSettings
    let items: [ClipItem]
    @State private var wallpaper = Self.loadWallpaper()

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                ContentCard(item: items[0], isSelected: true, width: 200, height: 120, lineLimit: 3)
                ContentCard(item: items[1], isSelected: false, width: 200, height: 120, lineLimit: 3)
            }
            PositionPill(text: "2 of 12")
        }
        .frame(maxWidth: .infinity)
        .frame(height: 300)
        .background {
            backdrop
            Color.black.opacity(appearance.backdropDim)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .environmentObject(appearance)
    }

    @ViewBuilder
    private var backdrop: some View {
        if let wallpaper {
            Image(nsImage: wallpaper)
                .resizable()
                .scaledToFill()
        } else {
            LinearGradient(colors: [.indigo, .purple, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private static func loadWallpaper() -> NSImage? {
        guard let screen = NSScreen.main, let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        return NSImage(contentsOf: url)
    }
}
