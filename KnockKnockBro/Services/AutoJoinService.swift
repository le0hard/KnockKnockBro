import Foundation

/// Определяет, какую встречу нужно предложить автоматически подключить
/// прямо сейчас, и предоставляет действие "Отменить Auto Join на сегодня".
///
/// Ключевое разделение ответственности с `WakeObserver`: этот сервис
/// отвечает только за ВПЕРЁД смотрящий триггер — "до старта осталось N
/// секунд, пора показывать countdown". Если момент триггера уже остался в
/// прошлом (например, Mac спал во время самого отсчёта), это не
/// "догоняющий" Auto Join, а зона ответственности `WakeObserver` и
/// `MissedMeetingPromptView` — они уже реализуют ровно нужное поведение
/// ("встреча началась N минут назад, показать промпт без автозапуска").
/// Auto Join и Missed Meeting не пересекаются по времени: первый работает
/// СТРОГО до `occurrence.startDate`, второй — СТРОГО после.
///
/// Как и `OccurrenceEngine`/`WakeObserver`, ключевая логика вынесена в
/// чистую статическую функцию — без побочных эффектов, легко тестируемую.
struct AutoJoinService {

    /// Находит ближайшую встречу, для которой прямо сейчас должен идти
    /// (или начинаться) обратный отсчёт Auto Join.
    ///
    /// Условия триггера:
    /// - `meeting.enabled == true` и `meeting.autoJoin?.isEnabled == true`;
    /// - на эту дату нет исключения с `isSkipped == true` или
    ///   `autoJoinCancelled == true`;
    /// - `now` находится в полуоткрытом окне
    ///   `[occurrence.startDate - countdown, occurrence.startDate)` —
    ///   отсчёт уже должен идти, но встреча ещё не началась.
    ///
    /// - Parameter alreadyTriggeredOccurrenceIDs: идентификаторы
    ///   occurrences (`MeetingOccurrence.id`), для которых панель уже была
    ///   показана — такие пропускаются, чтобы не показывать её повторно
    ///   после того, как пользователь явно взаимодействовал с ней или она
    ///   была отменена в рамках той же самой проверки.
    static func occurrenceToTrigger(
        meetings: [Meeting],
        exceptions: [MeetingOccurrenceException],
        defaultCountdown: TimeInterval,
        alreadyTriggeredOccurrenceIDs: Set<String> = [],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> MeetingOccurrence? {
        let candidates = meetings.filter { meeting in
            meeting.enabled && meeting.type == .scheduled && (meeting.autoJoin?.isEnabled ?? false)
        }
        guard !candidates.isEmpty else { return nil }

        // Достаточно небольшого диапазона вперёд — самый длинный
        // поддерживаемый countdown (произвольное значение) на практике не
        // будет больше нескольких минут; берём час с запасом.
        let range = DateInterval(start: now, duration: 60 * 60)
        let occurrences = OccurrenceEngine.occurrences(
            for: candidates, in: range, exceptions: exceptions, calendar: calendar
        )

        for occurrence in occurrences {
            if alreadyTriggeredOccurrenceIDs.contains(occurrence.id) { continue }

            if isAutoJoinCancelled(for: occurrence, exceptions: exceptions, calendar: calendar) { continue }

            let countdown = resolvedCountdown(for: occurrence.meeting, defaultCountdown: defaultCountdown)
            let triggerStart = occurrence.startDate.addingTimeInterval(-countdown)

            if now >= triggerStart && now < occurrence.startDate {
                return occurrence
            }
        }

        return nil
    }

    /// Countdown, применимый к конкретной встрече: её собственное
    /// переопределение, если задано, иначе — глобальное значение по
    /// умолчанию из `AppSettingsStore`.
    static func resolvedCountdown(for meeting: Meeting, defaultCountdown: TimeInterval) -> TimeInterval {
        meeting.autoJoin?.countdownOverride ?? defaultCountdown
    }

    private static func isAutoJoinCancelled(
        for occurrence: MeetingOccurrence,
        exceptions: [MeetingOccurrenceException],
        calendar: Calendar
    ) -> Bool {
        exceptions.contains {
            ($0.isSkipped || $0.autoJoinCancelled)
                && $0.matches(meetingID: occurrence.meeting.id, date: occurrence.startDate, calendar: calendar)
        }
    }
}
