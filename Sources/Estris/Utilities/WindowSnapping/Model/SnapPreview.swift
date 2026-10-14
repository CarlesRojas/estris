import AppKit
import SwiftUI

/// The outline showing where a dragged window will snap: rounded like a window, with a dark
/// see-through fill, or frosted like the Clipboard Manager's cards when chosen in Settings. It
/// sits just behind the dragged window, grows out of the screen edge or corner being dragged
/// to, and glides between areas as the pointer moves; with Reduce Motion, it only fades.
@MainActor
final class SnapPreview {
    /// Room between the outline and the area, so it reads as a preview of it.
    private static let inset: CGFloat = 6
    /// About the corners of a macOS window.
    fileprivate static let cornerRadius: CGFloat = 16
    /// Room around the outline for the frosted look's shadow.
    fileprivate static let shadowRoom: CGFloat = 32
    private static let duration: TimeInterval = 0.18
    /// The frosted look's blur, lighter than the overlays' (SwiftUI's regular material blurs
    /// 60 points), so what's behind reads through it.
    private static let blurRadius: CGFloat = 30

    private lazy var panel: NSPanel = {
        let panel = PreviewPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        hosting.sizingOptions = []
        panel.contentView = hosting
        return panel
    }()

    private lazy var hosting = BlurHostingView(rootView: PreviewBox(isFrosted: false), blurRadius: Self.blurRadius)

    private var shown: NSRect?

    /// Shows the outline over `area`, growing from `edge` if it isn't showing yet, just behind
    /// the window numbered `below` (in front of everything else when unknown); `isFrosted`
    /// gives it the Clipboard Manager's frosted look instead of the dark one.
    func show(_ area: NSRect, from edge: SnapEdge, below window: CGWindowID?, isFrosted: Bool) {
        let target = area.insetBy(dx: Self.inset, dy: Self.inset)
        guard target != shown else { return }
        if shown == nil {
            hosting.rootView = PreviewBox(isFrosted: isFrosted)
            panel.setFrame(Self.panelFrame(for: edge.startRect(for: target)), display: false)
            panel.alphaValue = 0
            if let window {
                panel.level = .normal
                panel.order(.below, relativeTo: Int(window))
            } else {
                panel.level = .floating
                panel.orderFrontRegardless()
            }
        }
        shown = target
        let frame = Self.panelFrame(for: target)
        // With Reduce Motion it doesn't grow or glide: it fades in where it lands.
        let reducesMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if reducesMotion { panel.setFrame(frame, display: true) }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            if !reducesMotion { panel.animator().setFrame(frame, display: true) }
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard shown != nil else { return }
        shown = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.duration
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                if self?.shown == nil { self?.panel.orderOut(nil) }
            }
        })
    }

    /// The panel's frame for an outline: larger, leaving room for the shadow.
    private static func panelFrame(for outline: NSRect) -> NSRect {
        outline.insetBy(dx: -shadowRoom, dy: -shadowRoom)
    }
}

/// Left where it's put: by default macOS moves a window down out of the menu bar, which would
/// push the outline of a top area (and the room for its shadow) below the screen's top.
private final class PreviewPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Sets the blur of the frosted material it hosts. SwiftUI offers no blur radius, so it's set
/// on the material's blur filter, again after each layout in case SwiftUI rebuilt it.
private final class BlurHostingView<Content: View>: NSHostingView<Content> {
    private let blurRadius: CGFloat

    init(rootView: Content, blurRadius: CGFloat) {
        self.blurRadius = blurRadius
        super.init(rootView: rootView)
    }

    required init(rootView: Content) {
        blurRadius = 0
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        if let layer { setBlur(in: layer) }
    }

    private func setBlur(in layer: CALayer) {
        if layer.filters?.contains(where: { ($0 as? NSObject)?.value(forKey: "name") as? String == "gaussianBlur" }) == true {
            layer.setValue(blurRadius, forKeyPath: "filters.gaussianBlur.inputRadius")
        }
        layer.sublayers?.forEach(setBlur(in:))
    }
}

/// The outline itself: an empty Clipboard Manager card in its default look, or dark and
/// see-through with a faint white border.
private struct PreviewBox: View {
    let isFrosted: Bool

    var body: some View {
        Group {
            if isFrosted {
                Color.clear
                    .surface(cornerRadius: SnapPreview.cornerRadius)
                    .environmentObject(AppearanceSettings(usesDefaults: true))
            } else {
                RoundedRectangle(cornerRadius: SnapPreview.cornerRadius, style: .continuous)
                    .fill(Color.black.opacity(0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: SnapPreview.cornerRadius, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.3), lineWidth: 2)
                    )
            }
        }
        .padding(SnapPreview.shadowRoom)
    }
}

/// The screen edge or corner a drag is snapping to, which the preview grows out of.
enum SnapEdge {
    case left, right, top, bottom, topLeft, topRight, bottomLeft, bottomRight

    /// A sliver of the target along the edge, or a dot at the corner.
    func startRect(for target: NSRect) -> NSRect {
        let size: CGFloat = 2
        switch self {
        case .left: return NSRect(x: target.minX, y: target.minY, width: size, height: target.height)
        case .right: return NSRect(x: target.maxX - size, y: target.minY, width: size, height: target.height)
        case .top: return NSRect(x: target.minX, y: target.maxY - size, width: target.width, height: size)
        case .bottom: return NSRect(x: target.minX, y: target.minY, width: target.width, height: size)
        case .topLeft: return NSRect(x: target.minX, y: target.maxY - size, width: size, height: size)
        case .topRight: return NSRect(x: target.maxX - size, y: target.maxY - size, width: size, height: size)
        case .bottomLeft: return NSRect(x: target.minX, y: target.minY, width: size, height: size)
        case .bottomRight: return NSRect(x: target.maxX - size, y: target.minY, width: size, height: size)
        }
    }
}
