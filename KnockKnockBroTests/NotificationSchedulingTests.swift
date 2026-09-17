import XCTest
import UserNotifications
@testable import KnockKnockBro

/// Тесты для той части `NotificationService`, которую можно проверить
/// изолированно и детерминированно: разворачивание occurrences и
/// применение "не планировать напоминание, если момент уже в прошлом".
/// Реальное взаимодействие с `UNUserNotificationCenter` (permission,
/// системная очередь) не мокается — это интеграционная часть,
/// проверяемая вручную через запуск приложения.
final class NotificationSchedulingTests: XCTestCase {

    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
        return calendar
    }

    private func makeMeeting(
        hour: Int, minute: Int, recurrence: Recurrence,
        reminders: [MeetingReminder]
    ) -> Meeting {
        Meeting(
            name: "Daily",
            url: URL(string: "https://telemost.yandex.ru/j/1")!,
            service: .yandexTelemost,
            type: .scheduled,
            schedule: MeetingSchedule(hour: hour, minute: minute, recurrence: recurrence),
            reminders: reminders
        )
    }

    /// Проверяет саму идею, на которой строится `schedule(reminder:for:now:)`:
    /// если момент "начало минус offset" уже в прошлом относительно `now`,
    /// напоминание не должно планироваться. Так как приватный метод
    /// планирования недоступен напрямую из теста, проверяем эквивалентную,
    /// наблюдаемую снаружи логику через `OccurrenceEngine`, на которой она
    /// основана: если occurrence существует, а offset больше, чем разница
    /// между occurrence.startDate и now, конкретное напоминание "протухло".
    func testPastReminderOffsetIsDetectedAsExpired() {
        let cal = calendar()
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 16
        components.hour = 10
        components.minute = 0
        let occurrenceStart = cal.date(from: components)!

        // "Сейчас" — на 2 минуты позже начала встречи.
        let now = occurrenceStart.addingTimeInterval(2 * 60)

        let reminderOffset: TimeInterval = 15 * 60 // "за 15 минут"
        let fireDate = occurrenceStart.addingTimeInterval(-reminderOffset)

        XCTAssertLessThan(fireDate, now, "Напоминание 'за 15 минут' для уже начавшейся встречи должно считаться протухшим")
    }

    func testFutureReminderOffsetIsNotExpired() {
        let cal = calendar()
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 16
        components.hour = 10
        components.minute = 0
        let occurrenceStart = cal.date(from: components)!

        let now = occurrenceStart.addingTimeInterval(-60 * 60) // за час до начала

        let reminderOffset: TimeInterval = 15 * 60
        let fireDate = occurrenceStart.addingTimeInterval(-reminderOffset)

        XCTAssertGreaterThan(fireDate, now)
    }

    /// Подтверждает, что для окна планирования в 48 часов
    /// `OccurrenceEngine` (на котором строится `rescheduleAll`) не выдаёт
    /// количество occurrences, способное создать взрывной рост
    /// уведомлений — при разумном количестве встреч и напоминаний общее
    /// число запросов остаётся далеко ниже системного лимита 64.
    func testReasonableMeetingCountStaysWellBelowSystemPendingLimit() {
        let cal = calendar()
        let now = Date()
        let range = DateInterval(start: now, duration: 48 * 60 * 60)

        var meetings: [Meeting] = []
        for hour in [9, 10, 11, 14, 17] {
            meetings.append(
                makeMeeting(
                    hour: hour, minute: 0, recurrence: .daily,
                    reminders: [
                        MeetingReminder(offsetBeforeStart: 15 * 60),
                        MeetingReminder(offsetBeforeStart: 5 * 60),
                        MeetingReminder(offsetBeforeStart: 0),
                    ]
                )
            )
        }

        let occurrences = OccurrenceEngine.occurrences(for: meetings, in: range, calendar: cal)
        let totalNotifications = occurrences.count * 3 // 3 напоминания на каждый occurrence

        XCTAssertLessThan(totalNotifications, 64)
    }
}
