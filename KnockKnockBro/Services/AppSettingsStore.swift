import Foundation
import Observation

/// Режим подключения к встречам Яндекс Телемоста.
enum TelemostConnectionMode: String, CaseIterable, Identifiable {
    case both
    case desktopOnly
    case webOnly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .both: return "Веб-версия и Desktop-приложение"
        case .desktopOnly: return "Только Desktop-приложение"
        case .webOnly: return "Только Веб-версия"
        }
    }
}

/// Лёгкое хранилище пользовательских настроек уровня приложения — в
/// отличие от `MeetingStore` (доменные данные о встречах, версионированный
/// JSON, экспортируемый пользователем), здесь живут локальные предпочтения.
/// Хранится через стандартный `UserDefaults`.
@Observable
final class AppSettingsStore {

    private enum Key {
        static let defaultAutoJoinCountdown = "defaultAutoJoinCountdown"
        static let showInMenuBar = "showInMenuBar"
        static let openMainWindowOnLaunch = "openMainWindowOnLaunch"
        static let telemostConnectionMode = "telemostConnectionMode"
    }

    static let fallbackDefaultCountdown: TimeInterval = 10

    private let defaults: UserDefaults

    var defaultAutoJoinCountdown: TimeInterval {
        didSet {
            defaults.set(defaultAutoJoinCountdown, forKey: Key.defaultAutoJoinCountdown)
        }
    }

    /// Показывать ли иконку KnockKnockBro в строке меню. Подключается к
    /// `MenuBarExtra(isInserted:)` — переключение применяется мгновенно,
    /// без перезапуска приложения.
    var showInMenuBar: Bool {
        didSet {
            defaults.set(showInMenuBar, forKey: Key.showInMenuBar)
        }
    }

    /// Открывать ли главное окно автоматически при запуске приложения.
    var openMainWindowOnLaunch: Bool {
        didSet {
            defaults.set(openMainWindowOnLaunch, forKey: Key.openMainWindowOnLaunch)
        }
    }

    /// Режим подключения к встречам Яндекс Телемоста — веб, desktop, или
    /// оба варианта одновременно. По умолчанию оба.
    var telemostConnectionMode: TelemostConnectionMode {
        didSet {
            defaults.set(telemostConnectionMode.rawValue, forKey: Key.telemostConnectionMode)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedCountdown = defaults.double(forKey: Key.defaultAutoJoinCountdown)
        self.defaultAutoJoinCountdown = storedCountdown > 0 ? storedCountdown : Self.fallbackDefaultCountdown

        if defaults.object(forKey: Key.showInMenuBar) != nil {
            self.showInMenuBar = defaults.bool(forKey: Key.showInMenuBar)
        } else {
            self.showInMenuBar = true
        }

        if defaults.object(forKey: Key.openMainWindowOnLaunch) != nil {
            self.openMainWindowOnLaunch = defaults.bool(forKey: Key.openMainWindowOnLaunch)
        } else {
            self.openMainWindowOnLaunch = false
        }

        if let rawValue = defaults.string(forKey: Key.telemostConnectionMode),
           let mode = TelemostConnectionMode(rawValue: rawValue) {
            self.telemostConnectionMode = mode
        } else {
            self.telemostConnectionMode = .both
        }
    }
}
