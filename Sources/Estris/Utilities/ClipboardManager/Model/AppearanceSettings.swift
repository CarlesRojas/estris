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

    /// The default look, for each row's Reset to Default.
    static let defaultTint = color(from: Stored().tint)
    static let defaultTintOpacity = Stored().tintOpacity
    static let defaultSelectedTintOpacity = Stored().selectedTintOpacity
    static let defaultShadowRadius = Stored().shadowRadius
    static let defaultBackdropDim = Stored().backdropDim

    private struct Stored: Codable {
        var tint: [Double] = [0.5, 0.5, 0.5]
        var tintOpacity = 0.2
        var selectedTintOpacity = 0.3
        var shadowRadius = 16.0
        var backdropDim = 0.5
    }

    /// The look as configured; `usesDefaults` gives the default look instead, without reading
    /// or saving anything, for other utilities' overlays.
    init(usesDefaults: Bool = false) {
        let saved = usesDefaults ? nil : UserDefaults.standard.data(forKey: Self.key)
        let stored = saved.flatMap { try? JSONDecoder().decode(Stored.self, from: $0) } ?? Stored()
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

    func surfaceTint(isSelected: Bool, isHovered: Bool = false) -> Color? {
        // Hover adds a third of the selection highlight, so it never reads as selected.
        let hover = isHovered && !isSelected ? selectedTintOpacity / 3 : 0
        let opacity = tintOpacity + (isSelected ? selectedTintOpacity : 0) + hover
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
