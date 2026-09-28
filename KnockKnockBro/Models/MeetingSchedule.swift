import Foundation

/// Правило повторения запланированной встречи.
///
/// Это описание ПРАВИЛА, а не конкретной даты. Отклонения для отдельных
/// дат (например, "Пропустить сегодня") хранятся отдельно, в
/// `MeetingOccurrenceException`, и не влияют на само правило — так что
/// пропуск одного дня никогда не портит остальное расписание.
enum Recurrence: Equatable, Hashable {
    /// Каждый день.
    case daily
    /// По будням (Пн–Пт).
    case weekdays
    /// Еженедельно, в один и тот же день недели.
    case weekly(Weekday)
    /// В выбранные дни недели (может быть несколько дней в неделе).
    case customDays(Set<Weekday>)
    /// Разовая встреча в конкретный день (v0.4.0).
    ///
    /// `autoDelete` — удалить встречу автоматически через час после
    /// начала (см. `MeetingStore.deleteExpiredOneTimeMeetings`). Без
    /// автоудаления прошедшая разовая встреча остаётся в списке, в
    /// разделе "Прошедшие". Флаг живёт внутри этого case, а не в
    /// `MeetingSchedule`, потому что для повторяющихся встреч он не имеет
    /// смысла.
    case once(CalendarDay, autoDelete: Bool)
}

extension Recurrence {
    /// День разовой встречи; `nil` для повторяющихся.
    var oneTimeDay: CalendarDay? {
        if case .once(let day, _) = self { return day }
        return nil
    }
}

// MARK: - Codable

extension Recurrence: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case weekday
        case weekdays
        case date
        case autoDelete
    }

    private enum Kind: String, Codable {
        case daily, weekdays, weekly, customDays, once
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .type)
        switch kind {
        case .daily:
            self = .daily
        case .weekdays:
            self = .weekdays
        case .weekly:
            let weekday = try container.decode(Weekday.self, forKey: .weekday)
            self = .weekly(weekday)
        case .customDays:
            let days = try container.decode(Set<Weekday>.self, forKey: .weekdays)
            self = .customDays(days)
        case .once:
            let day = try container.decode(CalendarDay.self, forKey: .date)
            let autoDelete = try container.decodeIfPresent(Bool.self, forKey: .autoDelete) ?? false
            self = .once(day, autoDelete: autoDelete)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .daily:
            try container.encode(Kind.daily, forKey: .type)
        case .weekdays:
            try container.encode(Kind.weekdays, forKey: .type)
        case .weekly(let weekday):
            try container.encode(Kind.weekly, forKey: .type)
            try container.encode(weekday, forKey: .weekday)
        case .customDays(let days):
            try container.encode(Kind.customDays, forKey: .type)
            try container.encode(days, forKey: .weekdays)
        case .once(let day, let autoDelete):
            try container.encode(Kind.once, forKey: .type)
            try container.encode(day, forKey: .date)
            try container.encode(autoDelete, forKey: .autoDelete)
        }
    }
}

/// Расписание запланированной встречи: время начала + правило повторения.
struct MeetingSchedule: Codable, Equatable, Hashable {
    /// Час начала, 0...23, в локальном времени пользователя.
    var hour: Int
    /// Минута начала, 0...59.
    var minute: Int
    var recurrence: Recurrence
}
