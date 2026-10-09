import AppKit
import SwiftUI

/// Which system API draws the overlay's surfaces.
enum SurfaceRenderer: String, CaseIterable, Identifiable {
    case swiftUIGlass
    case appKitGlass
    case vibrancy
    case material

    var id: Self { self }

    var title: String {
        switch self {
        case .swiftUIGlass: "Liquid Glass (SwiftUI)"
        case .appKitGlass: "Liquid Glass (AppKit)"
        case .vibrancy: "Vibrancy (NSVisualEffectView)"
        case .material: "Material (SwiftUI)"
        }
    }

    var needsMacOS26: Bool {
        self == .swiftUIGlass || self == .appKitGlass
    }
}

enum VibrancyMaterial: String, CaseIterable, Identifiable {
    case hudWindow, popover, menu, sidebar, headerView, sheet, windowBackground, fullScreenUI, toolTip, underWindowBackground

    var id: Self { self }

    var title: String {
        switch self {
        case .hudWindow: "HUD window"
        case .popover: "Popover"
        case .menu: "Menu"
        case .sidebar: "Sidebar"
        case .headerView: "Header view"
        case .sheet: "Sheet"
        case .windowBackground: "Window background"
        case .fullScreenUI: "Full screen UI"
        case .toolTip: "Tooltip"
        case .underWindowBackground: "Under window background"
        }
    }

    var nsMaterial: NSVisualEffectView.Material {
        switch self {
        case .hudWindow: .hudWindow
        case .popover: .popover
        case .menu: .menu
        case .sidebar: .sidebar
        case .headerView: .headerView
        case .sheet: .sheet
        case .windowBackground: .windowBackground
        case .fullScreenUI: .fullScreenUI
        case .toolTip: .toolTip
        case .underWindowBackground: .underWindowBackground
        }
    }
}

/// How the overlay looks, persisted in UserDefaults.
@MainActor
final class AppearanceSettings: ObservableObject {
    @Published var renderer: SurfaceRenderer { didSet { save() } }
    @Published var vibrancyMaterial: VibrancyMaterial { didSet { save() } }
    @Published var tint: Color { didSet { save() } }
    @Published var tintOpacity: Double { didSet { save() } }
    @Published var selectedTintOpacity: Double { didSet { save() } }
    @Published var interactive: Bool { didSet { save() } }
    @Published var shadowRadius: Double { didSet { save() } }
    @Published var backdropDim: Double { didSet { save() } }

    private static let key = "appearance"

    private struct Stored: Codable {
        var renderer = SurfaceRenderer.material.rawValue
        var vibrancyMaterial = VibrancyMaterial.hudWindow.rawValue
        var tint: [Double] = [0, 0, 0]
        var tintOpacity = 0.2
        var selectedTintOpacity = 0.3
        var interactive = false
        var shadowRadius = 16.0
        var backdropDim = 0.0
    }

    init() {
        let stored = UserDefaults.standard.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(Stored.self, from: $0) } ?? Stored()
        renderer = SurfaceRenderer(rawValue: stored.renderer) ?? .material
        vibrancyMaterial = VibrancyMaterial(rawValue: stored.vibrancyMaterial) ?? .hudWindow
        tint = Self.color(from: stored.tint)
        tintOpacity = stored.tintOpacity
        selectedTintOpacity = stored.selectedTintOpacity
        interactive = stored.interactive
        shadowRadius = stored.shadowRadius
        backdropDim = stored.backdropDim
    }

    func reset() {
        let defaults = Stored()
        renderer = SurfaceRenderer(rawValue: defaults.renderer) ?? .material
        vibrancyMaterial = VibrancyMaterial(rawValue: defaults.vibrancyMaterial) ?? .hudWindow
        tint = Self.color(from: defaults.tint)
        tintOpacity = defaults.tintOpacity
        selectedTintOpacity = defaults.selectedTintOpacity
        interactive = defaults.interactive
        shadowRadius = defaults.shadowRadius
        backdropDim = defaults.backdropDim
    }

    func surfaceTint(isSelected: Bool) -> Color? {
        let opacity = tintOpacity + (isSelected ? selectedTintOpacity : 0)
        return opacity > 0 ? tint.opacity(min(opacity, 1)) : nil
    }

    private func save() {
        var stored = Stored()
        stored.renderer = renderer.rawValue
        stored.vibrancyMaterial = vibrancyMaterial.rawValue
        stored.tint = Self.components(of: tint)
        stored.tintOpacity = tintOpacity
        stored.selectedTintOpacity = selectedTintOpacity
        stored.interactive = interactive
        stored.shadowRadius = shadowRadius
        stored.backdropDim = backdropDim
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    private static func color(from components: [Double]) -> Color {
        guard components.count == 3 else { return .black }
        return Color(.sRGB, red: components[0], green: components[1], blue: components[2])
    }

    private static func components(of color: Color) -> [Double] {
        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return [1, 1, 1] }
        return [srgb.redComponent, srgb.greenComponent, srgb.blueComponent].map(Double.init)
    }
}

private struct InPreviewKey: EnvironmentKey {
    static let defaultValue = false
}

private struct SolidKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Inside the settings preview, vibrancy blends with the preview backdrop instead of
    /// whatever is behind the settings window.
    var surfaceInPreview: Bool {
        get { self[InPreviewKey.self] }
        set { self[InPreviewKey.self] = newValue }
    }

    /// Solid cards instead of a backdrop effect. Glass and blur sample what is behind them
    /// and do not survive 3D transforms, so tilted views use this.
    var surfaceIsSolid: Bool {
        get { self[SolidKey.self] }
        set { self[SolidKey.self] = newValue }
    }
}

extension View {
    /// Background for overlay elements, drawn as configured in Appearance.
    /// Pass `.infinity` as the radius for a capsule.
    func surface(cornerRadius: CGFloat, isSelected: Bool = false) -> some View {
        modifier(Surface(cornerRadius: cornerRadius, isSelected: isSelected))
    }
}

private struct Surface: ViewModifier {
    let cornerRadius: CGFloat
    let isSelected: Bool
    @EnvironmentObject private var appearance: AppearanceSettings
    @Environment(\.surfaceInPreview) private var inPreview
    @Environment(\.surfaceIsSolid) private var isSolid

    @ViewBuilder
    func body(content: Content) -> some View {
        Group {
            if isSolid {
                content
                    .background(shape.fill(tint ?? .clear))
                    .background(shape.fill(Color(nsColor: .windowBackgroundColor)))
            } else {
                backdrop(content)
            }
        }
        .background {
            if appearance.shadowRadius > 0 {
                OuterShadow(shape: shape, radius: appearance.shadowRadius, opacity: isSelected ? 0.35 : 0.22)
            }
        }
    }

    private var shape: AnyShape {
        cornerRadius.isInfinite
            ? AnyShape(Capsule())
            : AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var tint: Color? {
        appearance.surfaceTint(isSelected: isSelected)
    }

    @ViewBuilder
    private func backdrop(_ content: Content) -> some View {
        switch appearance.renderer {
        case .swiftUIGlass:
            if #available(macOS 26, *) {
                content.glassEffect(swiftUIGlass, in: shape)
            } else {
                materialBackdrop(content)
            }
        case .appKitGlass:
            if #available(macOS 26, *) {
                content.background(GeometryReader { proxy in
                    AppKitGlass(cornerRadius: clampedRadius(proxy.size), tint: tint.map { NSColor($0) })
                })
            } else {
                materialBackdrop(content)
            }
        case .vibrancy:
            content
                .background(shape.fill(tint ?? .clear))
                .background(GeometryReader { proxy in
                    VibrancyBackdrop(
                        material: appearance.vibrancyMaterial.nsMaterial,
                        cornerRadius: clampedRadius(proxy.size),
                        blending: inPreview ? .withinWindow : .behindWindow
                    )
                })
        case .material:
            materialBackdrop(content)
        }
    }

    private func materialBackdrop(_ content: Content) -> some View {
        content
            .background(shape.fill(tint ?? .clear))
            .background(.regularMaterial, in: shape)
    }

    @available(macOS 26, *)
    private var swiftUIGlass: Glass {
        var glass = Glass.regular
        if let tint {
            glass = glass.tint(tint)
        }
        return appearance.interactive ? glass.interactive() : glass
    }

    private func clampedRadius(_ size: CGSize) -> CGFloat {
        min(cornerRadius, size.width / 2, size.height / 2)
    }
}

@available(macOS 26, *)
private struct AppKitGlass: NSViewRepresentable {
    let cornerRadius: CGFloat
    let tint: NSColor?

    func makeNSView(context: Context) -> NSGlassEffectView {
        NSGlassEffectView()
    }

    func updateNSView(_ view: NSGlassEffectView, context: Context) {
        view.cornerRadius = cornerRadius
        view.tintColor = tint
    }
}

private struct VibrancyBackdrop: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let cornerRadius: CGFloat
    let blending: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        // The overlay belongs to an app that is never active; keep the effect live anyway.
        view.state = .active
        view.wantsLayer = true
        view.layer?.masksToBounds = true
        view.layer?.cornerCurve = .continuous
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
        view.layer?.cornerRadius = cornerRadius
    }
}

/// A shadow drawn only outside `shape`. A plain `.shadow` on the whole view also shadows
/// the text and shows through translucent surfaces, darkening secondary text.
private struct OuterShadow: View {
    let shape: AnyShape
    let radius: CGFloat
    let opacity: Double

    var body: some View {
        shape
            .fill(Color.black)
            .shadow(color: .black.opacity(opacity), radius: radius, y: radius / 3)
            .mask {
                ZStack {
                    // Negative padding draws past the frame without changing the layout size.
                    Rectangle().padding(-radius * 4)
                    shape.fill(Color.black).blendMode(.destinationOut)
                }
                .compositingGroup()
            }
    }
}
