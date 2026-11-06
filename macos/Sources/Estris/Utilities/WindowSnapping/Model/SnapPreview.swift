import AppKit
import SwiftUI

/// The outline showing where a dragged window will snap: rounded like a window, with a dark
/// see-through fill, or frosted like the Clipboard Manager's cards when chosen in Settings. It
/// sits just behind the dragged window, grows out of the screen edge or corner being dragged
/// to, and glides between areas as the pointer moves; with Reduce Motion, it only fades.
///
/// The panel covers the whole screen and stays put, and only the outline inside it moves:
/// SwiftUI animates that smoothly at the display's rate, where resizing a window frame by
/// frame would stutter.
@MainActor
final class SnapPreview {
    /// Room between the outline and the area, so it reads as a preview of it.
    private static let inset: CGFloat = 6
    /// About the corners of a macOS window.
    fileprivate static let cornerRadius: CGFloat = 16
    private static let fadeDuration: TimeInterval = 0.18
    /// A spring keeps the outline's speed when the pointer picks another area mid-glide,
    /// instead of starting over from rest.
    private static let glide = Animation.spring(response: 0.28, dampingFraction: 0.9)
    /// The frosted look's blur, lighter than the overlays' (SwiftUI's regular material blurs
    /// 60 points), so what's behind reads through it.
    private static let blurRadius: CGFloat = 30

    private let model = PreviewModel()

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

    private lazy var hosting = BlurHostingView(rootView: PreviewCanvas(model: model), blurRadius: Self.blurRadius)

    private var shown: NSRect?
    /// Counts hides, so a fade that ends after the outline came back doesn't take it away.
    private var hides = 0

    /// Shows the outline over `area`, growing from `edge` if it isn't showing yet, just behind
    /// the window numbered `below` (in front of everything else when unknown); `isFrosted`
    /// gives it the Clipboard Manager's frosted look instead of the dark one.
    func show(_ area: NSRect, from edge: SnapEdge, below window: CGWindowID?, isFrosted: Bool) {
        let target = area.insetBy(dx: Self.inset, dy: Self.inset)
        guard target != shown else { return }
        let reducesMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: target.midX, y: target.midY)) }?.frame ?? target
        let isNew = shown == nil || panel.frame != screen
        shown = target
        hides += 1

        guard isNew else {
            withAnimation(reducesMotion ? nil : Self.glide) { model.rect = local(target) }
            return
        }
        // Starts from the edge, unseen, then grows and fades in once that has been drawn.
        panel.setFrame(screen, display: false)
        model.isFrosted = isFrosted
        model.isVisible = false
        model.rect = local(reducesMotion ? target : edge.startRect(for: target))
        if let window {
            panel.level = .normal
            panel.order(.below, relativeTo: Int(window))
        } else {
            panel.level = .floating
            panel.orderFrontRegardless()
        }
        DispatchQueue.main.async { [self] in
            MainActor.assumeIsolated {
                guard shown == target else { return }
                withAnimation(.easeOut(duration: Self.fadeDuration)) { model.isVisible = true }
                withAnimation(reducesMotion ? nil : Self.glide) { model.rect = local(target) }
            }
        }
    }

    func hide() {
        guard shown != nil else { return }
        shown = nil
        hides += 1
        let hide = hides
        withAnimation(.easeOut(duration: Self.fadeDuration)) { model.isVisible = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.fadeDuration) { [self] in
            MainActor.assumeIsolated {
                if hides == hide { panel.orderOut(nil) }
            }
        }
    }

    /// A rect on the screen in the panel's own coordinates, from its top left.
    private func local(_ rect: NSRect) -> CGRect {
        CGRect(x: rect.minX - panel.frame.minX, y: panel.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }
}

@MainActor
private final class PreviewModel: ObservableObject {
    @Published var rect = CGRect.zero
    @Published var isVisible = false
    @Published var isFrosted = false
}

/// Left where it's put: by default macOS moves a window down out of the menu bar, which would
/// push a panel covering the screen below its top.
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

/// The whole screen, with the outline placed where the model says.
private struct PreviewCanvas: View {
    @ObservedObject var model: PreviewModel

    var body: some View {
        PreviewBox(isFrosted: model.isFrosted)
            .frame(width: model.rect.width, height: model.rect.height)
            .offset(x: model.rect.minX, y: model.rect.minY)
            .opacity(model.isVisible ? 1 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The outline itself: an empty Clipboard Manager card in its default look, or dark and
/// see-through with a faint white border.
private struct PreviewBox: View {
    let isFrosted: Bool

    var body: some View {
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
