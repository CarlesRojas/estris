import Foundation
import SwiftUI

/// Formats a moment as short date and time, such as "Oct 9 14:05", per General settings.
struct DateTimeFormat: Equatable {
    var language = AppLanguage.system
    var dateStyle = DateStyle.monthDay
    var timeStyle = TimeStyle.system

    func string(from date: Date) -> String {
        Self.formatter(language.locale, "\(dateStyle.pattern) \(timePattern)").string(from: date)
    }

    /// The date part alone, for showing the choices in Settings.
    func dateString(from date: Date) -> String {
        Self.formatter(language.locale, dateStyle.pattern).string(from: date)
    }

    func timeString(from date: Date) -> String {
        Self.formatter(language.locale, timePattern).string(from: date)
    }

    /// Formatters are slow to make and every overlay step draws a date; one per locale and
    /// pattern is kept. `NSCache` is safe to use from any thread.
    private static let formatters = NSCache<NSString, DateFormatter>()

    private static func formatter(_ locale: Locale, _ pattern: String) -> DateFormatter {
        let key = "\(locale.identifier)|\(pattern)" as NSString
        if let cached = formatters.object(forKey: key) { return cached }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = pattern
        formatters.setObject(formatter, forKey: key)
        return formatter
    }

    private var timePattern: String {
        switch timeStyle {
        case .twentyFourHour: "HH:mm"
        case .twelveHour: "h:mm a"
        // Follows the 12/24-hour choice in System Settings.
        case .system: DateFormatter.dateFormat(fromTemplate: "j:mm", options: 0, locale: .current) ?? "HH:mm"
        }
    }
}

private struct DateTimeFormatKey: EnvironmentKey {
    static let defaultValue = DateTimeFormat()
}

extension EnvironmentValues {
    var dateTimeFormat: DateTimeFormat {
        get { self[DateTimeFormatKey.self] }
        set { self[DateTimeFormatKey.self] = newValue }
    }
}
