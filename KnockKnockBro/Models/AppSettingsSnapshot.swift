import Foundation

/// Снимок настроек приложения для экспорта/импорта (формат 3, v0.6.0).
///
/// Сами настройки живут в `UserDefaults` (`AppSettingsStore`) и в системе
/// (автозапуск — `SMAppService`, см. `LoginItemService`); этот тип — только
/// их переносимое представление в JSON-файле экспорта. В файл хранения
/// встреч на диске (`meetings.json`) он не пишется.
struct AppSettingsSnapshot: Codable, Equatable {
    /// Отсчёт Auto Join по умолчанию, в секундах.
    var defaultAutoJoinCountdown: TimeInterval
    /// Режим подключения к Яндекс Телемосту.
    var telemostConnectionMode: TelemostConnectionMode
    /// За сколько минут до начала нажатие "Подключиться" засчитывается.
    var joinCountingWindowMinutes: Int
    /// Показывать иконку в строке меню.
    var showInMenuBar: Bool
    /// Открывать главное окно при запуске.
    var openMainWindowOnLaunch: Bool
    /// Запускать KnockKnockBro при входе в macOS.
    var launchAtLogin: Bool

    /// Допустимый диапазон отсчёта Auto Join — от 1 секунды до часа.
    static let countdownRange: ClosedRange<TimeInterval> = 1...3600
    /// Допустимый диапазон окна засчитывания — как у степпера в Настройках.
    static let joinCountingWindowRange: ClosedRange<Int> = 0...120

    /// `true`, если все числовые значения в допустимых пределах.
    var isValid: Bool {
        Self.countdownRange.contains(defaultAutoJoinCountdown)
            && Self.joinCountingWindowRange.contains(joinCountingWindowMinutes)
    }
}
