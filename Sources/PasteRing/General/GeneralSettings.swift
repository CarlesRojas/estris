import Foundation
import SwiftUI

/// The app's language. Translations live in Resources/Localization, one folder per language.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case spanish = "es"
    case french = "fr"
    case portuguese = "pt-BR"
    case german = "de"
    case italian = "it"
    case catalan = "ca"

    var id: Self { self }

    /// Each language in itself, so it can be found whatever language the app is in.
    var title: String {
        switch self {
        case .system: String(localized: "Same as System")
        case .english: "English"
        case .spanish: "Español"
        case .french: "Français"
        case .portuguese: "Português (Brasil)"
        case .german: "Deutsch"
        case .italian: "Italiano"
        case .catalan: "Català"
        }
    }

    /// The locale dates are written in.
    var locale: Locale {
        self == .system ? .current : Locale(identifier: rawValue)
    }

    /// Makes macOS load this language for PasteRing from the next launch.
    func apply() {
        if self == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([rawValue], forKey: "AppleLanguages")
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
        case .system: String(localized: "System setting")
        case .twentyFourHour: String(localized: "24-hour")
        case .twelveHour: String(localized: "12-hour")
        }
    }
}

/// Settings shared by every utility in the app, persisted in UserDefaults.
@MainActor
final class GeneralSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Keys.language)
            language.apply()
        }
    }

    /// The language PasteRing started in; a change applies after relaunching.
    let launchLanguage: AppLanguage

    @Published var dateStyle: DateStyle {
        didSet { defaults.set(dateStyle.rawValue, forKey: Keys.dateStyle) }
    }

    @Published var timeStyle: TimeStyle {
        didSet { defaults.set(timeStyle.rawValue, forKey: Keys.timeStyle) }
    }

    /// Unlocked by clicking the version in General > About six times.
    @Published var showsDeveloperSettings: Bool {
        didSet { defaults.set(showsDeveloperSettings, forKey: Keys.showsDeveloperSettings) }
    }

    init() {
        let defaults = UserDefaults.standard
        language = AppLanguage(rawValue: defaults.string(forKey: Keys.language) ?? "") ?? .system
        launchLanguage = language
        dateStyle = DateStyle(rawValue: defaults.string(forKey: Keys.dateStyle) ?? "") ?? .monthDay
        timeStyle = TimeStyle(rawValue: defaults.string(forKey: Keys.timeStyle) ?? "") ?? .system
        showsDeveloperSettings = defaults.bool(forKey: Keys.showsDeveloperSettings)
    }

    var dateTimeFormat: DateTimeFormat {
        DateTimeFormat(language: language, dateStyle: dateStyle, timeStyle: timeStyle)
    }

    private enum Keys {
        static let language = "language"
        static let dateStyle = "dateStyle"
        static let timeStyle = "timeStyle"
        static let showsDeveloperSettings = "showsDeveloperSettings"
    }
}
