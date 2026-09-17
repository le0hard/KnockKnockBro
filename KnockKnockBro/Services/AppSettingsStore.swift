import Foundation
import Observation

/// Лёгкое хранилище пользовательских настроек уровня приложения — в
/// отличие от `MeetingStore` (доменные данные о встречах, версионированный
/// JSON, экспортируемый пользователем), здесь живут локальные предпочтения
/// вроде глобального countdown по умолчанию и переключателей экрана
/// Settings. Хранится через стандартный `UserDefaults`, как и полагается
/// для таких настроек в приложениях для macOS.
@Observable
final class AppSettingsStore {

    private enum Key {
        static let defaultAutoJoinCountdown = "defaultAutoJoinCountdown"
        static let showInMenuBar = "showInMenuBar"
        static let openMainWindowOnLaunch = "openMainWindowOnLaunch"
    }

    /// Значение по умолчанию, если пользователь ещё ничего не настраивал —
    /// совпадает с тем, что показано на макете интерфейса.
    static let fallbackDefaultCountdown: TimeInterval = 10

    private let defaults: UserDefaults

    /// Глобальное значение обратного отсчёта перед автоподключением,
    /// используемое для встреч, у которых `AutoJoinSettings.countdownOverride
    /// == nil`.
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
    /// По умолчанию `false` — приложение по умолчанию стартует только в
    /// Menu Bar, без открытия окна.
    var openMainWindowOnLaunch: Bool {
        didSet {
            defaults.set(openMainWindowOnLaunch, forKey: Key.openMainWindowOnLaunch)
        }
    }

    /// - Parameter defaults: `UserDefaults`, используемый для хранения.
    ///   Вынесен наружу, чтобы тесты могли подставить изолированный
    ///   suite и не трогать реальные настройки пользователя.
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
    }
}
