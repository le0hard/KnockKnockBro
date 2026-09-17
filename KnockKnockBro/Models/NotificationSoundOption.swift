import Foundation

/// Звук, который проигрывается при показе напоминания.
///
/// Намеренно ограничен небольшим фиксированным набором пресетов, а не
/// произвольным выбором звукового файла. Сопоставление пресета с конкретным
/// звуковым файлом (или системным звуком по умолчанию) происходит в
/// `NotificationService` — модель хранит только выбор пользователя, а не
/// механизм воспроизведения.
enum NotificationSoundOption: String, Codable, CaseIterable, Equatable, Hashable {
    /// Системный звук уведомления по умолчанию.
    case system
    /// Короткий, менее навязчивый сигнал.
    case short
    /// Без звука.
    case none

    var displayName: String {
        switch self {
        case .system: return "По умолчанию"
        case .short: return "KnockKnockSound"
        case .none: return "Без звука"
        }
    }
    
}
