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
    /// Picked with the scroll wheel, opened with Return.
    @Published var selected: CGWindowID?
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
                    isSelected: state.selected == window.id,
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
    let isSelected: Bool
    let open: () -> Void
    let close: () -> Void
    @State private var isHovered = false

    /// The window's shape, within reason for very wide or tall ones.
    private var width: CGFloat {
        height * min(max(window.aspect, 0.6), 2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // The app's icon and the window's name at the top left, the × at the right.
            HStack(spacing: 6) {
                if let appIcon {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 16, height: 16)
                }
                Text(verbatim: window.title.isEmpty ? appName : window.title)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                if showsClose {
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(CloseButtonStyle())
                    .help("Close Window")
                }
            }
            .frame(width: width)

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
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.primary.opacity(isHovered || isSelected ? 0.12 : 0))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .onHover { isHovered = $0 }
    }
}

/// Just the ×, faint until the pointer is on it, darker while pressed.
private struct CloseButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CloseButtonLabel(configuration: configuration)
    }

    private struct CloseButtonLabel: View {
        let configuration: Configuration
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .foregroundStyle(Color.primary.opacity(configuration.isPressed ? 1 : isHovered ? 0.8 : 0.35))
                .onHover { isHovered = $0 }
        }
    }
}
