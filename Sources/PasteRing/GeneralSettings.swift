import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"

    var id: Self { self }

    var title: String {
        switch self {
        case .english: "English"
        }
    }
}

/// How dates are written across the app, without the year.
enum DateStyle: String, CaseIterable, Identifiable {
    case monthDay
    case dayMonth
    case numericMonthDay
    case numericDayMonth

    var id: Self { self }

    var pattern: String {
        switch self {
        case .monthDay: "MMM d"
        case .dayMonth: "d MMM"
        case .numericMonthDay: "M/d"
        case .numericDayMonth: "d/M"
        }
    }
}

enum TimeStyle: String, CaseIterable, Identifiable {
    case system
    case twentyFourHour
    case twelveHour

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "System setting"
        case .twentyFourHour: "24-hour"
        case .twelveHour: "12-hour"
        }
    }
}

/// Settings shared by every utility in the app, persisted in UserDefaults.
@MainActor
final class GeneralSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: Keys.language) }
    }

    @Published var dateStyle: DateStyle {
        didSet { defaults.set(dateStyle.rawValue, forKey: Keys.dateStyle) }
    }

    @Published var timeStyle: TimeStyle {
        didSet { defaults.set(timeStyle.rawValue, forKey: Keys.timeStyle) }
    }

    init() {
        let defaults = UserDefaults.standard
        language = AppLanguage(rawValue: defaults.string(forKey: Keys.language) ?? "") ?? .english
        dateStyle = DateStyle(rawValue: defaults.string(forKey: Keys.dateStyle) ?? "") ?? .monthDay
        timeStyle = TimeStyle(rawValue: defaults.string(forKey: Keys.timeStyle) ?? "") ?? .system
    }

    var dateTimeFormat: DateTimeFormat {
        DateTimeFormat(language: language, dateStyle: dateStyle, timeStyle: timeStyle)
    }

    private enum Keys {
        static let language = "language"
        static let dateStyle = "dateStyle"
        static let timeStyle = "timeStyle"
    }
}

/// Formats a moment as short date and time, such as "Oct 9 14:05", per General settings.
struct DateTimeFormat: Equatable {
    var language = AppLanguage.english
    var dateStyle = DateStyle.monthDay
    var timeStyle = TimeStyle.system

    func string(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.rawValue)
        formatter.dateFormat = "\(dateStyle.pattern) \(timePattern)"
        return formatter.string(from: date)
    }

    /// The date part alone, for showing the choices in Settings.
    func dateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.rawValue)
        formatter.dateFormat = dateStyle.pattern
        return formatter.string(from: date)
    }

    func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.rawValue)
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
