import Foundation

/// How long the pointer stays over something before it acts: a window to focus, a Dock icon
/// to preview.
enum HoverDelay: Int, CaseIterable, Identifiable {
    case immediately = 0
    case ms100 = 100
    case ms250 = 250
    case ms500 = 500
    case ms1000 = 1000

    var id: Self { self }

    var seconds: TimeInterval { TimeInterval(rawValue) / 1000 }

    /// "Immediately", or "250 ms" in the app's language.
    var title: String {
        if self == .immediately { return String(localized: "Immediately") }
        return Measurement(value: Double(rawValue), unit: UnitDuration.milliseconds)
            .formatted(.measurement(width: .abbreviated))
    }
}
