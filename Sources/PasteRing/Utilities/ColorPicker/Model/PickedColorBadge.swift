import AppKit
import SwiftUI

/// A small badge by the pointer for a moment after picking: the color and what was copied.
@MainActor
final class PickedColorBadge {
    private static let visibleFor: TimeInterval = 1.6

    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(_ color: NSColor, text: String) {
        let view = NSHostingView(rootView: BadgeView(color: Color(nsColor: color), text: text))
        let size = view.fittingSize
        let point = NSEvent.mouseLocation
        let frame = NSRect(x: point.x + 16, y: point.y - size.height - 16, width: size.width, height: size.height)

        let panel = self.panel ?? Self.makePanel()
        self.panel = panel
        panel.contentView = view
        panel.setFrame(frame, display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let panel = self?.panel else { return }
                NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; panel.animator().alphaValue = 0 }, completionHandler: {
                    MainActor.assumeIsolated { panel.orderOut(nil) }
                })
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.visibleFor, execute: work)
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        return panel
    }
}

private struct BadgeView: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(color)
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.white.opacity(0.4), lineWidth: 1))
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(text)
                    .font(.system(.body, design: .monospaced))
                Text("Copied")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .fixedSize()
    }
}
