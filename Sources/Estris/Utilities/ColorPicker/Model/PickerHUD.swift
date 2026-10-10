import AppKit
import SwiftUI

/// What the picker shows by the pointer.
@MainActor
final class PickerHUDModel: ObservableObject {
    /// The magnified area under the pointer; nil once picked, leaving only the label.
    @Published var loupe: CGImage?
    @Published var color: NSColor = .clear
    @Published var text = ""
    @Published var isCopied = false
}

/// The loupe centred on the pointer, with a label under it: the color and its value in the
/// chosen format, and "Copied" once picked. Floats above everything and lets clicks through.
@MainActor
final class PickerHUD {
    static let loupeSize: CGFloat = 128
    private static let gap: CGFloat = 10
    private static let width: CGFloat = 320
    private static let height: CGFloat = loupeSize + gap + 64
    private static let visibleAfterPicking: TimeInterval = 1.6

    let model = PickerHUDModel()
    private var hideWork: DispatchWorkItem?

    private lazy var panel: NSPanel = {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: PickerHUDView(model: model)
            .environmentObject(AppearanceSettings(usesDefaults: true)))
        return panel
    }()

    /// Puts the loupe's centre on the pointer.
    func move(to point: NSPoint) {
        let frame = NSRect(x: point.x - Self.width / 2, y: point.y + Self.loupeSize / 2 - Self.height,
                           width: Self.width, height: Self.height)
        panel.setFrame(frame, display: true)
        if !panel.isVisible {
            hideWork?.cancel()
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        }
    }

    /// After picking: the loupe goes, the label says Copied, then fades out.
    func showPicked(_ color: NSColor, text: String, at point: NSPoint) {
        model.loupe = nil
        model.color = color
        model.text = text
        model.isCopied = true
        move(to: point)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.visibleAfterPicking, execute: work)
    }

    func hide() {
        hideWork?.cancel()
        panel.orderOut(nil)
    }
}

private struct PickerHUDView: View {
    @ObservedObject var model: PickerHUDModel

    var body: some View {
        VStack(spacing: 10) {
            Group {
                if let loupe = model.loupe {
                    Loupe(image: loupe)
                } else {
                    Color.clear
                }
            }
            .frame(width: PickerHUD.loupeSize, height: PickerHUD.loupeSize)

            ColorLabel(color: Color(nsColor: model.color), text: model.text, isCopied: model.isCopied)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// The pixels under the pointer, magnified, with the centre one outlined.
private struct Loupe: View {
    let image: CGImage

    var body: some View {
        let cell = PickerHUD.loupeSize / CGFloat(max(image.width, 1))
        ZStack {
            Image(decorative: image, scale: 1)
                .interpolation(.none)
                .resizable()
            Rectangle()
                .strokeBorder(.white, lineWidth: 1)
                .background(Rectangle().strokeBorder(.black.opacity(0.6), lineWidth: 2))
                .frame(width: cell + 2, height: cell + 2)
        }
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 2))
        .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
    }
}

/// A capsule with the color in a circle at the left, concentric with the capsule's end, and
/// the value centred to its right.
private struct ColorLabel: View {
    private static let padding: CGFloat = 7
    private static let swatch: CGFloat = 30

    let color: Color
    let text: String
    let isCopied: Bool

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                .frame(width: Self.swatch, height: Self.swatch)
            VStack(spacing: 1) {
                Text(verbatim: text)
                    .font(.system(.callout, design: .monospaced).weight(.medium))
                if isCopied {
                    Text("Copied")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 80)
            .padding(.trailing, Self.swatch / 2)
        }
        .padding(Self.padding)
        .frame(minHeight: Self.swatch + 2 * Self.padding)
        .surface(cornerRadius: .infinity)
        .fixedSize()
    }
}
