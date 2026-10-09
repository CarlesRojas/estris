import Foundation

/// Looks up a key that is only known at run time, such as an enum's raw value, in the app's
/// translations (Resources/Localization). Text written in code uses `String(localized:)`, and
/// literal text in SwiftUI views is translated on its own.
func localized(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: nil, table: nil)
}
