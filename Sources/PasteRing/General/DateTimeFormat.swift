import Foundation
import SwiftUI

/// Formats a moment as short date and time, such as "Oct 9 14:05", per General settings.
struct DateTimeFormat: Equatable {
    var language = AppLanguage.system
    var dateStyle = DateStyle.monthDay
    var timeStyle = TimeStyle.system

    func string(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateFormat = "\(dateStyle.pattern) \(timePattern)"
        return formatter.string(from: date)
    }

    /// The date part alone, for showing the choices in Settings.
    func dateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateFormat = dateStyle.pattern
        return formatter.string(from: date)
    }

    func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateFormat = timePattern
        return formatter.string(from: date)
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
