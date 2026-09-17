import Foundation

/// Настройки автоматического подключения для конкретной встречи.
struct AutoJoinSettings: Codable, Equatable, Hashable {
    var isEnabled: Bool
    /// Длительность обратного отсчёта перед автоподключением, в секундах.
    /// `nil` означает "использовать глобальное значение по умолчанию из
    /// Настроек" — переопределение per-meeting является опциональным.
    var countdownOverride: TimeInterval?

    init(isEnabled: Bool = false, countdownOverride: TimeInterval? = nil) {
        self.isEnabled = isEnabled
        self.countdownOverride = countdownOverride
    }
}
