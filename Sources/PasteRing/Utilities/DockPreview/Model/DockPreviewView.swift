import AppKit
import SwiftUI

/// What the panel shows: the app under the pointer and its windows.
@MainActor
final class DockPreviewState: ObservableObject {
    @Published var app: NSRunningApplication?
    @Published var windows: [AppWindow] = []
    @Published var thumbnails: [CGWindowID: CGImage] = [:]
    /// Windows whose × works (Accessibility reaches them).
    @Published var closable: Set<CGWindowID> = []
    /// Side by side above a bottom Dock; one above the other beside a left or right one.
    @Published var isHorizontal = true
}

/// The previews in the frosted panel, in the clipboard overlay's default look. A click on one
/// brings its window forward; its × closes it.
struct DockPreviewView: View {
    @ObservedObject var state: DockPreviewState
    @ObservedObject var settings: DockPreviewSettings
    let open: (AppWindow) -> Void
    let close: (AppWindow) -> Void

    private static let padding: CGFloat = 8
    private static let cardRadius: CGFloat = 10

    var body: some View {
        let layout = state.isHorizontal
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 4))
            : AnyLayout(VStackLayout(spacing: 4))
        layout {
            ForEach(state.windows) { window in
                PreviewCard(
                    window: window,
                    appName: state.app?.localizedName ?? "",
                    appIcon: state.app?.icon,
                    thumbnail: state.thumbnails[window.id],
                    height: CGFloat(settings.size),
                    cornerRadius: Self.cardRadius,
                    showsClose: settings.showsCloseButton && state.closable.contains(window.id),
                    open: { open(window) },
                    close: { close(window) }
                )
            }
        }
        .padding(Self.padding)
        // Concentric with the cards.
        .surface(cornerRadius: Self.cardRadius + Self.padding)
    }
}

private struct PreviewCard: View {
    let window: AppWindow
    let appName: String
    let appIcon: NSImage?
    let thumbnail: CGImage?
    let height: CGFloat
    let cornerRadius: CGFloat
    let showsClose: Bool
    let open: () -> Void
    let close: () -> Void
    @State private var isHovered = false

    /// The window's shape, within reason for very wide or tall ones.
    private var width: CGFloat {
        height * min(max(window.aspect, 0.6), 2)
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius - 4, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
                if let thumbnail {
                    Image(decorative: thumbnail, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else if let appIcon {
                    // Until the thumbnail arrives, or without Screen Recording: the same size of
                    // card, with the app's icon in the middle.
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: min(96, height * 0.5), height: min(96, height * 0.5))
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius - 4, style: .continuous))
            Text(verbatim: window.title.isEmpty ? appName : window.title)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: width)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.primary.opacity(isHovered ? 0.12 : 0))
        )
        .overlay(alignment: .topTrailing) {
            if showsClose && isHovered {
                Button(action: close) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.black.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("Close Window")
                .padding(2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .onHover { isHovered = $0 }
    }
}
