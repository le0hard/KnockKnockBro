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
}

// MARK: - Codable

extension Recurrence: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case weekday
        case weekdays
    }

    private enum Kind: String, Codable {
        case daily, weekdays, weekly, customDays
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
