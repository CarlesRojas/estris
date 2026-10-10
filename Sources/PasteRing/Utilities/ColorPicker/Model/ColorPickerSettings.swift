import AppKit
import Carbon.HIToolbox

/// How a picked color is copied.
enum ColorFormat: String, CaseIterable, Identifiable {
    case hex
    case rgb
    case hsl
    case swiftUI

    var id: Self { self }

    var title: String {
        switch self {
        case .hex: "Hex"
        case .rgb: "RGB"
        case .hsl: "HSL"
        case .swiftUI: "SwiftUI"
        }
    }

    /// The color as text in this format, from sRGB components between 0 and 1.
    func string(red: Double, green: Double, blue: Double, hashPrefix: Bool) -> String {
        let r = Int((red * 255).rounded())
        let g = Int((green * 255).rounded())
        let b = Int((blue * 255).rounded())
        switch self {
        case .hex:
            return (hashPrefix ? "#" : "") + String(format: "%02X%02X%02X", r, g, b)
        case .rgb:
            return "rgb(\(r), \(g), \(b))"
        case .hsl:
            let (h, s, l) = Self.hsl(red: red, green: green, blue: blue)
            return "hsl(\(Int(h.rounded())), \(Int((s * 100).rounded()))%, \(Int((l * 100).rounded()))%)"
        case .swiftUI:
            return String(format: "Color(red: %.3f, green: %.3f, blue: %.3f)", red, green, blue)
        }
    }

    func string(for color: NSColor, hashPrefix: Bool) -> String {
        let srgb = color.usingColorSpace(.sRGB) ?? color
        return string(red: srgb.redComponent, green: srgb.greenComponent, blue: srgb.blueComponent, hashPrefix: hashPrefix)
    }

    /// Hue in degrees, saturation and lightness between 0 and 1.
    private static func hsl(red: Double, green: Double, blue: Double) -> (Double, Double, Double) {
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let lightness = (maximum + minimum) / 2
        let delta = maximum - minimum
        guard delta > 0 else { return (0, 0, lightness) }
        let saturation = delta / (1 - abs(2 * lightness - 1))
        var hue: Double
        switch maximum {
        case red: hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
        case green: hue = (blue - red) / delta + 2
        default: hue = (red - green) / delta + 4
        }
        hue *= 60
        if hue < 0 { hue += 360 }
        return (hue, saturation, lightness)
    }
}

/// Color Picker preferences, persisted in UserDefaults.
@MainActor
final class ColorPickerSettings: ObservableObject {
    static let defaultShortcut = Shortcut(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(cmdKey | shiftKey), keyLabel: "C")

    private let defaults = UserDefaults.standard

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.isEnabled) }
    }

    @Published var format: ColorFormat {
        didSet { defaults.set(format.rawValue, forKey: Keys.format) }
    }

    /// Hex values start with "#".
    @Published var hashPrefix: Bool {
        didSet { defaults.set(hashPrefix, forKey: Keys.hashPrefix) }
    }

    @Published var shortcut: Shortcut {
        didSet { defaults.set(try? JSONEncoder().encode(shortcut), forKey: Keys.shortcut) }
    }

    /// The colors picked lately, most recent first, as sRGB hex ("FF8000"). Kept by Reset to
    /// Defaults, like other histories.
    @Published private(set) var recentColors: [String] {
        didSet { defaults.set(recentColors, forKey: Keys.recentColors) }
    }

    static let maxRecentColors = 16

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [Keys.hashPrefix: true])
        isEnabled = defaults.bool(forKey: Keys.isEnabled)
        format = ColorFormat(rawValue: defaults.string(forKey: Keys.format) ?? "") ?? .hex
        hashPrefix = defaults.bool(forKey: Keys.hashPrefix)
        recentColors = defaults.stringArray(forKey: Keys.recentColors) ?? []
        shortcut = defaults.data(forKey: Keys.shortcut).flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) } ?? Self.defaultShortcut
    }

    /// Puts a color first among the recent ones; picking one again moves it up.
    func remember(_ color: NSColor) {
        let hex = ColorFormat.hex.string(for: color, hashPrefix: false)
        recentColors = Array(([hex] + recentColors.filter { $0 != hex }).prefix(Self.maxRecentColors))
    }

    func clearRecentColors() {
        recentColors = []
    }

    /// Back to the default format and shortcut; the on/off switch and recent colors stay.
    func reset() {
        format = .hex
        hashPrefix = true
        shortcut = Self.defaultShortcut
    }

    private enum Keys {
        static let isEnabled = "colorPickerEnabled"
        static let format = "colorPickerFormat"
        static let hashPrefix = "colorPickerHashPrefix"
        static let shortcut = "colorPickerShortcut"
        static let recentColors = "colorPickerRecentColors"
    }
}

extension NSColor {
    /// An sRGB color from "FF8000"; nil for anything else.
    convenience init?(hex: String) {
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
