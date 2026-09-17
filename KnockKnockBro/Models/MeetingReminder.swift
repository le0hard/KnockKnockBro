import Foundation

/// Одно независимое напоминание о встрече.
///
/// У Scheduled Meeting может быть произвольное количество напоминаний —
/// это обеспечивается тем, что `Meeting.reminders` — обычный массив, без
/// какого-либо фиксированного лимита в модели.
struct MeetingReminder: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    /// Сколько секунд до начала встречи показать напоминание.
    /// 0 означает "в момент начала".
    var offsetBeforeStart: TimeInterval
    var sound: NotificationSoundOption

    init(id: UUID = UUID(), offsetBeforeStart: TimeInterval, sound: NotificationSoundOption = .system) {
        self.id = id
        self.offsetBeforeStart = offsetBeforeStart
        self.sound = sound
    }
}
