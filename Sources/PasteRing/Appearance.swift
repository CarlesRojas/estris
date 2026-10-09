import AppKit
import SwiftUI

/// How the overlay looks, persisted in UserDefaults.
@MainActor
final class AppearanceSettings: ObservableObject {
    @Published var tint: Color { didSet { save() } }
    @Published var tintOpacity: Double { didSet { save() } }
    @Published var selectedTintOpacity: Double { didSet { save() } }
    @Published var shadowRadius: Double { didSet { save() } }
    @Published var backdropDim: Double { didSet { save() } }

    private static let key = "appearance"

    private struct Stored: Codable {
        var tint: [Double] = [0.5, 0.5, 0.5]
        var tintOpacity = 0.2
        var selectedTintOpacity = 0.3
        var shadowRadius = 16.0
        var backdropDim = 0.0
    }

    init() {
        let stored = UserDefaults.standard.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(Stored.self, from: $0) } ?? Stored()
        tint = Self.color(from: stored.tint)
        tintOpacity = stored.tintOpacity
        selectedTintOpacity = stored.selectedTintOpacity
        shadowRadius = stored.shadowRadius
        backdropDim = stored.backdropDim
    }

    func reset() {
        let defaults = Stored()
        tint = Self.color(from: defaults.tint)
        tintOpacity = defaults.tintOpacity
        selectedTintOpacity = defaults.selectedTintOpacity
        shadowRadius = defaults.shadowRadius
        backdropDim = defaults.backdropDim
    }

    func surfaceTint(isSelected: Bool) -> Color? {
        let opacity = tintOpacity + (isSelected ? selectedTintOpacity : 0)
        return opacity > 0 ? tint.opacity(min(opacity, 1)) : nil
    }

    private func save() {
        let stored = Stored(
            tint: Self.components(of: tint),
            tintOpacity: tintOpacity,
            selectedTintOpacity: selectedTintOpacity,
            shadowRadius: shadowRadius,
            backdropDim: backdropDim
        )
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    private static func color(from components: [Double]) -> Color {
        guard components.count == 3 else { return Color(.sRGB, red: 0.5, green: 0.5, blue: 0.5) }
        return Color(.sRGB, red: components[0], green: components[1], blue: components[2])
    }

    private static func components(of color: Color) -> [Double] {
        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return [0.5, 0.5, 0.5] }
        return [srgb.redComponent, srgb.greenComponent, srgb.blueComponent].map(Double.init)
    }
}

extension View {
    /// Frosted material background for overlay elements, tinted as configured in Appearance.
    /// Pass `.infinity` as the radius for a capsule.
    func surface(cornerRadius: CGFloat, isSelected: Bool = false) -> some View {
        modifier(Surface(cornerRadius: cornerRadius, isSelected: isSelected))
    }
}

private struct Surface: ViewModifier {
    let cornerRadius: CGFloat
    let isSelected: Bool
    @EnvironmentObject private var appearance: AppearanceSettings

    func body(content: Content) -> some View {
        content
            .background(shape.fill(appearance.surfaceTint(isSelected: isSelected) ?? .clear))
            .background(.regularMaterial, in: shape)
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
