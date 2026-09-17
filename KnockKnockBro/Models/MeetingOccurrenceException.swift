import Foundation

/// Точечное исключение из правила повторения одной встречи на КОНКРЕТНУЮ
/// календарную дату.
///
/// Это то, что позволяет "Пропустить сегодня" и "Отменить автоподключение
/// на сегодня" не трогать `MeetingSchedule`/`AutoJoinSettings` вообще —
/// вместо изменения самого правила мы добавляем отдельную запись, которую
/// учитывает `OccurrenceEngine`/`AutoJoinService` при разворачивании
/// расписания. Следующее повторение (завтра, через неделю и т.д.) при этом
/// продолжает работать по исходному правилу как ни в чём не бывало.
///
/// `isSkipped` и `autoJoinCancelled` — независимые флаги: "Пропустить
/// сегодня" отменяет и уведомления, и Auto Join этого дня, тогда как
/// "Отмена" в countdown-панели Auto Join отменяет ТОЛЬКО автоподключение,
/// оставляя обычные уведомления (Join/Snooze) этого дня активными.
struct MeetingOccurrenceException: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var meetingID: UUID

    /// Календарный день, к которому относится исключение, хранится как
    /// год/месяц/день без времени и часового пояса — так исключение
    /// однозначно и человекочитаемо в JSON, а сравнение с конкретным
    /// экземпляром встречи всегда идёт через `Calendar`, приводящую обе
    /// стороны к одной и той же гранулярности "день".
    var year: Int
    var month: Int
    var day: Int

    var isSkipped: Bool

    /// `true`, если пользователь нажал "Отмена" на countdown-панели Auto
    /// Join для этого конкретного дня. Не влияет на обычные уведомления —
    /// только на срабатывание автоматического подключения.
    var autoJoinCancelled: Bool

    init(
        id: UUID = UUID(),
        meetingID: UUID,
        date: Date,
        isSkipped: Bool = false,
        autoJoinCancelled: Bool = false,
        calendar: Calendar = .current
    ) {
        self.id = id
        self.meetingID = meetingID
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.year = components.year ?? 0
        self.month = components.month ?? 0
        self.day = components.day ?? 0
        self.isSkipped = isSkipped
        self.autoJoinCancelled = autoJoinCancelled
    }

    private enum CodingKeys: String, CodingKey {
        case id, meetingID, year, month, day, isSkipped, autoJoinCancelled
    }

    /// Ручной `Decodable` — чтобы файлы, сохранённые ДО появления
    /// `autoJoinCancelled`, продолжали загружаться без ошибок:
    /// отсутствующий ключ трактуется как `false`, а не как повод отклонить
    /// весь файл. Тот же принцип "мягкой" обратной совместимости, что и
    /// у `MeetingStore.StorageFile` для поля `exceptions`.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        meetingID = try container.decode(UUID.self, forKey: .meetingID)
        year = try container.decode(Int.self, forKey: .year)
        month = try container.decode(Int.self, forKey: .month)
        day = try container.decode(Int.self, forKey: .day)
        isSkipped = try container.decode(Bool.self, forKey: .isSkipped)
        autoJoinCancelled = try container.decodeIfPresent(Bool.self, forKey: .autoJoinCancelled) ?? false
    }

    /// `true`, если это исключение относится к указанной встрече и к тому
    /// же календарному дню, что и переданная дата.
    func matches(meetingID: UUID, date: Date, calendar: Calendar = .current) -> Bool {
        guard self.meetingID == meetingID else { return false }
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return components.year == year && components.month == month && components.day == day
    }
}
