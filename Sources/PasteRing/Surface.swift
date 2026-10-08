import SwiftUI

enum GlassStyle: String, CaseIterable, Identifiable {
    case frosted
    case clear

    var id: Self { self }

    var title: String {
        switch self {
        case .frosted: "Frosted"
        case .clear: "Clear"
        }
    }
}

private struct GlassStyleKey: EnvironmentKey {
    static let defaultValue = GlassStyle.frosted
}

extension EnvironmentValues {
    var glassStyle: GlassStyle {
        get { self[GlassStyleKey.self] }
        set { self[GlassStyleKey.self] = newValue }
    }
}

extension View {
    /// Background for overlay elements: Liquid Glass on macOS 26, blur materials before.
    func surface<S: Shape>(_ shape: S, isSelected: Bool = false) -> some View {
        modifier(Surface(shape: shape, isSelected: isSelected))
    }
}

private struct Surface<S: Shape>: ViewModifier {
    let shape: S
    let isSelected: Bool
    @Environment(\.glassStyle) private var style

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(glass, in: shape)
        } else {
            content
                .background(material, in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.18), lineWidth: 0.5))
                .shadow(color: .black.opacity(isSelected ? 0.25 : 0.12), radius: isSelected ? 14 : 6, y: 4)
        }
    }

    @available(macOS 26, *)
    private var glass: Glass {
        let base: Glass = style == .frosted ? .regular : .clear
        // A faint lift instead of a coloured border marks the selection.
        return isSelected ? base.tint(Color.white.opacity(0.12)) : base
    }

    private var material: Material {
        switch style {
        case .frosted: isSelected ? .thickMaterial : .regularMaterial
        case .clear: isSelected ? .thinMaterial : .ultraThinMaterial
        }
    }
}
