import Foundation

/// Правила учёта подключения к встрече (v0.5.0).
///
/// Нажатие "Подключиться" засчитывается как "уже на встрече", только если
/// оно сделано не раньше чем за `windowMinutes` минут до начала и в тот же
/// календарный день — в том числе после начала (опоздал и подключился).
/// Клик заранее (например, чтобы проверить ссылку за час) просто открывает
/// ссылку и ни на что не влияет.
///
/// Чистая логика без состояния — легко тестируется; запись отметки делает
/// `MeetingStore.markJoined`.
enum JoinTracking {

    /// Значение настройки по умолчанию, в минутах.
    static let defaultCountingWindowMinutes = 15

    /// Засчитывается ли нажатие в момент `now` для экземпляра встречи,
    /// начинающегося в `occurrenceStart`.
    static func countsAsJoin(
        occurrenceStart: Date,
        now: Date,
        windowMinutes: Int,
        calendar: Calendar = .current
    ) -> Bool {
        guard calendar.isDate(occurrenceStart, inSameDayAs: now) else { return false }
        let windowStart = occurrenceStart.addingTimeInterval(-TimeInterval(max(0, windowMinutes)) * 60)
        return now >= windowStart
    }

    /// Сегодняшний экземпляр встречи — для мест, где известна только сама
    /// встреча, а не конкретный экземпляр (строка главного окна).
    /// Исключения намеренно не учитываются: если пользователь подключился к
    /// встрече, которую до этого пропустил, подключение всё равно реально.
    static func todayOccurrence(of meeting: Meeting, now: Date, calendar: Calendar = .current) -> MeetingOccurrence? {
        let dayStart = calendar.startOfDay(for: now)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
        return OccurrenceEngine.occurrences(
            for: meeting, in: DateInterval(start: dayStart, end: dayEnd), calendar: calendar
        ).first
    }
}

extension MeetingStore {
    /// Засчитывает нажатие "Подключиться", если оно попадает в окно
    /// `JoinTracking.countsAsJoin`. Для Quick Room и встреч без экземпляра
    /// сегодня ничего не делает.
    ///
    /// - Parameter occurrenceStart: начало конкретного экземпляра, если он
    ///   известен в месте вызова (попап, календарь, уведомление); `nil` —
    ///   взять сегодняшний экземпляр встречи.
    /// - Returns: `true`, если отметка поставлена (или уже стояла).
    @discardableResult
    func recordJoinIfEligible(
        meeting: Meeting,
        occurrenceStart: Date? = nil,
        windowMinutes: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard meeting.type == .scheduled else { return false }
        guard let start = occurrenceStart ?? JoinTracking.todayOccurrence(of: meeting, now: now, calendar: calendar)?.startDate,
              JoinTracking.countsAsJoin(occurrenceStart: start, now: now, windowMinutes: windowMinutes, calendar: calendar)
        else { return false }
        markJoined(meetingID: meeting.id, on: start, calendar: calendar)
        return true
    }
}
