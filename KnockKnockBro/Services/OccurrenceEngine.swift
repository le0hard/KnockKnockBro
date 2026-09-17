import Foundation

/// Разворачивает ПРАВИЛО повторения Scheduled Meeting в конкретные
/// календарные экземпляры в заданном диапазоне дат.
///
/// Намеренно сделан чистым и не хранящим состояние компонентом: никакой
/// персистентности, никаких побочных эффектов, никакой зависимости от
/// `MeetingStore`. Именно это позволяет тестировать его исчерпывающе для
/// каждого типа повторения и каждого капризного календарного случая
/// (полночь, границы месяца, переход на летнее/зимнее время) без
/// необходимости поднимать весь контекст приложения.
///
/// `exceptions` позволяет учитывать точечные отклонения от правила на
/// конкретную дату (см. "Пропустить сегодня", `MeetingOccurrenceException`)
/// — это НЕ меняет само правило повторения, а лишь исключает один
/// конкретный день из результата, оставляя остальные дни нетронутыми.
struct OccurrenceEngine {

    /// Вычисляет все экземпляры одной встречи, чьё время начала попадает
    /// в `range` (полуоткрытый интервал: `range.start` включительно,
    /// `range.end` исключая).
    ///
    /// - Quick Room (`schedule == nil`) никогда не даёт экземпляров — у
    ///   него нет правила повторения для разворачивания.
    /// - Выключенная встреча (`enabled == false`) никогда не даёт
    ///   экземпляров — это то, что гарантирует отсутствие уведомлений и
    ///   Auto Join для выключенной встречи (требование Enable/Disable).
    /// - День, на который есть исключение с `isSkipped == true`, не
    ///   попадает в результат — при этом остальные дни продолжают
    ///   разворачиваться по правилу как обычно.
    static func occurrences(
        for meeting: Meeting,
        in range: DateInterval,
        exceptions: [MeetingOccurrenceException] = [],
        calendar: Calendar = .current
    ) -> [MeetingOccurrence] {
        guard meeting.enabled, let schedule = meeting.schedule else { return [] }
        guard range.duration > 0 else { return [] }

        var results: [MeetingOccurrence] = []
        var dayCursor = calendar.startOfDay(for: range.start)
        let rangeEnd = range.end

        // Идём по дням, а не вычисляем закрытой формулой: именно это
        // делает переход на летнее/зимнее время и границы месяца/года
        // "просто работающими" — каждый день его настоящее начало суток и
        // день недели спрашиваются у `Calendar`, который уже знает
        // локальные правила, вместо того чтобы мы сами реализовывали
        // календарную арифметику вручную.
        while dayCursor < rangeEnd {
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayCursor) else {
                break // защита от теоретически некорректных дат; на практике не должно происходить
            }

            if recurrence(schedule.recurrence, matches: dayCursor, calendar: calendar),
               let startDate = calendar.date(
                   bySettingHour: schedule.hour,
                   minute: schedule.minute,
                   second: 0,
                   of: dayCursor
               ),
               startDate >= range.start, startDate < range.end {
                let isSkipped = exceptions.contains {
                    $0.isSkipped && $0.matches(meetingID: meeting.id, date: startDate, calendar: calendar)
                }
                if !isSkipped {
                    results.append(MeetingOccurrence(meeting: meeting, startDate: startDate, calendar: calendar))
                }
            }
            // Если `bySettingHour` не смог построить дату (крайний случай:
            // указанное время физически не существует в этот день из-за
            // перевода стрелок вперёд, например 02:30 в ночь перехода) —
            // экземпляр в этот день просто не создаётся. Для встреч в
            // рабочие часы это не встречается на практике.

            dayCursor = nextDay
        }

        return results
    }

    /// Вычисляет экземпляры для нескольких встреч одновременно, объединяя
    /// и сортируя их по времени начала. Удобно для вызывающего кода (UI,
    /// `NotificationService`), которому нужно "всё, что происходит в этом
    /// окне", а не экземпляры одной встречи.
    static func occurrences(
        for meetings: [Meeting],
        in range: DateInterval,
        exceptions: [MeetingOccurrenceException] = [],
        calendar: Calendar = .current
    ) -> [MeetingOccurrence] {
        meetings
            .flatMap { occurrences(for: $0, in: range, exceptions: exceptions, calendar: calendar) }
            .sorted { $0.startDate < $1.startDate }
    }

    // MARK: - Recurrence matching

    private static func recurrence(_ recurrence: Recurrence, matches day: Date, calendar: Calendar) -> Bool {
        let weekdayNumber = calendar.component(.weekday, from: day)
        guard let weekday = Weekday(rawValue: weekdayNumber) else { return false }

        switch recurrence {
        case .daily:
            return true
        case .weekdays:
            return weekday != .sunday && weekday != .saturday
        case .weekly(let targetDay):
            return weekday == targetDay
        case .customDays(let days):
            return days.contains(weekday)
        }
    }
}
