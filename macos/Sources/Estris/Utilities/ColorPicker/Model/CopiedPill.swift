import AppKit
import SwiftUI

/// After picking: a pill by the pointer with the color and the copied value, which fades
/// out after a moment. Floats above everything and lets clicks through.
@MainActor
final class CopiedPill {
    private static let visibleFor: TimeInterval = 1.6
    /// Room between the pointer and the pill.
    private static let offset: CGFloat = 18

    private var hideWork: DispatchWorkItem?

    private lazy var panel: NSPanel = {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        return panel
    }()

    func show(_ color: NSColor, text: String) {
        let view = NSHostingView(rootView: PillView(color: Color(nsColor: color), text: text)
            // Room for the shadow around the pill.
            .padding(24)
            .environmentObject(AppearanceSettings(usesDefaults: true)))
        let size = view.fittingSize
        let point = NSEvent.mouseLocation
        panel.contentView = view
        panel.setFrame(NSRect(x: point.x - size.width / 2, y: point.y - Self.offset - size.height + 24, width: size.width, height: size.height), display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let panel = self?.panel else { return }
                NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; panel.animator().alphaValue = 0 }, completionHandler: {
                    MainActor.assumeIsolated { panel.orderOut(nil) }
                })
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.visibleFor, execute: work)
    }
}

/// A capsule in the clipboard overlay's default frosted look: the color in a circle at the
/// left, concentric with the capsule's end, and the value with "Copied" centred to its right.
private struct PillView: View {
    private static let padding: CGFloat = 7
    private static let swatch: CGFloat = 30

    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                .frame(width: Self.swatch, height: Self.swatch)
            VStack(spacing: 1) {
                Text(verbatim: text)
                    .font(.system(.callout, design: .monospaced).weight(.medium))
                Text("Copied")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 80)
            .padding(.trailing, Self.swatch / 2)
        }
        .padding(Self.padding)
        .surface(cornerRadius: .infinity)
        .fixedSize()
    }
}
