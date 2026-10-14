import AppKit
import SwiftUI

/// The outline showing where a dragged window will snap: rounded, with a dark see-through
/// fill, or frosted like the overlays when chosen in Settings. It grows out of the screen edge
/// or corner being dragged to, and glides between areas as the pointer moves; with Reduce
/// Motion, it only fades.
@MainActor
final class SnapPreview {
    /// Room between the outline and the area, so it reads as a preview of it.
    private static let inset: CGFloat = 6
    private static let cornerRadius: CGFloat = 20
    private static let duration: TimeInterval = 0.18
    /// The frosted fill is lighter than the overlays': thinner material, and see-through so
    /// what's behind reads through the blur.
    private static let frostedOpacity: Double = 0.75

    private lazy var panel: NSPanel = {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = Self.cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.borderWidth = 2
        view.layer?.borderColor = NSColor.white.withAlphaComponent(0.3).cgColor
        view.layer?.masksToBounds = true
        frosted.frame = view.bounds
        frosted.autoresizingMask = [.width, .height]
        view.addSubview(frosted)
        panel.contentView = view
        return panel
    }()

    private lazy var frosted = NSHostingView(rootView: FrostedFill(opacity: Self.frostedOpacity))

    private var shown: NSRect?

    /// Shows the outline over `area`, growing from `edge` if it isn't showing yet; `isFrosted`
    /// gives it the overlays' frosted fill instead of the dark one.
    func show(_ area: NSRect, from edge: SnapEdge, isFrosted: Bool) {
        let target = area.insetBy(dx: Self.inset, dy: Self.inset)
        guard target != shown else { return }
        if shown == nil {
            frosted.isHidden = !isFrosted
            panel.contentView?.layer?.backgroundColor = isFrosted ? nil : NSColor.black.withAlphaComponent(0.3).cgColor
            panel.setFrame(edge.startRect(for: target), display: false)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        shown = target
        // With Reduce Motion it doesn't grow or glide: it fades in where it lands.
        let reducesMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if reducesMotion { panel.setFrame(target, display: true) }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            if !reducesMotion { panel.animator().setFrame(target, display: true) }
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
}

/// The overlays' default frosted look, thinner and more see-through.
private struct FrostedFill: View {
    let opacity: Double

    var body: some View {
        Rectangle()
            .fill(AppearanceSettings(usesDefaults: true).surfaceTint(isSelected: false) ?? .clear)
            .background(.thinMaterial)
            .opacity(opacity)
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
