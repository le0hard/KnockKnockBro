import XCTest
@testable import KnockKnockBro

final class OccurrenceEngineTests: XCTestCase {

    // MARK: - Helpers

    private func makeScheduledMeeting(
        name: String = "Test Meeting",
        hour: Int,
        minute: Int,
        recurrence: Recurrence,
        enabled: Bool = true
    ) -> Meeting {
        Meeting(
            name: name,
            url: URL(string: "https://telemost.yandex.ru/j/1")!,
            service: .yandexTelemost,
            type: .scheduled,
            enabled: enabled,
            schedule: MeetingSchedule(hour: hour, minute: minute, recurrence: recurrence)
        )
    }

    /// Календарь с фиксированным часовым поясом — тесты не должны зависеть
    /// от локальных настроек машины, на которой они запускаются.
    private func calendar(timeZoneIdentifier: String = "Europe/Moscow") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier)!
        return calendar
    }

    private func localDate(
        year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0,
        calendar: Calendar
    ) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }

    // MARK: - Recurrence kinds

    func testDailyRecurrenceProducesOccurrenceEveryDayInRange() {
        let cal = calendar()
        let meeting = makeScheduledMeeting(hour: 10, minute: 0, recurrence: .daily)
        let range = DateInterval(
            start: localDate(year: 2026, month: 9, day: 14, calendar: cal),
            end: localDate(year: 2026, month: 9, day: 19, calendar: cal) // 5 дней: 14..18
        )

        let occurrences = OccurrenceEngine.occurrences(for: meeting, in: range, calendar: cal)

        XCTAssertEqual(occurrences.count, 5)
        XCTAssertEqual(occurrences.first?.startDate, localDate(year: 2026, month: 9, day: 14, hour: 10, calendar: cal))
        XCTAssertEqual(occurrences.last?.startDate, localDate(year: 2026, month: 9, day: 18, hour: 10, calendar: cal))
    }

    func testWeekdaysRecurrenceExcludesWeekends() {
        let cal = calendar()
        let meeting = makeScheduledMeeting(hour: 9, minute: 0, recurrence: .weekdays)
        // 2026-09-14 — понедельник. Диапазон в 7 дней: Пн..Вс.
        let range = DateInterval(
            start: localDate(year: 2026, month: 9, day: 14, calendar: cal),
            end: localDate(year: 2026, month: 9, day: 21, calendar: cal)
        )

        let occurrences = OccurrenceEngine.occurrences(for: meeting, in: range, calendar: cal)

        XCTAssertEqual(occurrences.count, 5)
        let days = occurrences.map { cal.component(.weekday, from: $0.startDate) }
        XCTAssertFalse(days.contains(Weekday.saturday.rawValue))
        XCTAssertFalse(days.contains(Weekday.sunday.rawValue))
    }

    func testWeeklyRecurrenceProducesOnlyMatchingWeekday() {
        let cal = calendar()
        let meeting = makeScheduledMeeting(hour: 14, minute: 30, recurrence: .weekly(.wednesday))
        // Две недели: 2026-09-14 (Пн) .. 2026-09-28 (Пн, исключая).
        let range = DateInterval(
            start: localDate(year: 2026, month: 9, day: 14, calendar: cal),
            end: localDate(year: 2026, month: 9, day: 28, calendar: cal)
        )

        let occurrences = OccurrenceEngine.occurrences(for: meeting, in: range, calendar: cal)

        XCTAssertEqual(occurrences.count, 2)
        for occurrence in occurrences {
            XCTAssertEqual(cal.component(.weekday, from: occurrence.startDate), Weekday.wednesday.rawValue)
        }
        XCTAssertEqual(occurrences[0].startDate, localDate(year: 2026, month: 9, day: 16, hour: 14, minute: 30, calendar: cal))
        XCTAssertEqual(occurrences[1].startDate, localDate(year: 2026, month: 9, day: 23, hour: 14, minute: 30, calendar: cal))
    }

    func testCustomDaysRecurrenceProducesOnlyOnSelectedDays() {
        let cal = calendar()
        let meeting = makeScheduledMeeting(
            hour: 17, minute: 0,
            recurrence: .customDays([.monday, .wednesday, .friday])
        )
        // Одна неделя: Пн (14) .. Вс (20).
        let range = DateInterval(
            start: localDate(year: 2026, month: 9, day: 14, calendar: cal),
            end: localDate(year: 2026, month: 9, day: 21, calendar: cal)
        )

        let occurrences = OccurrenceEngine.occurrences(for: meeting, in: range, calendar: cal)

        XCTAssertEqual(occurrences.count, 3)
        let weekdays = Set(occurrences.map { cal.component(.weekday, from: $0.startDate) })
        XCTAssertEqual(weekdays, [Weekday.monday.rawValue, Weekday.wednesday.rawValue, Weekday.friday.rawValue])
    }

    // MARK: - Enable/Disable and meeting type

    func testDisabledMeetingProducesNoOccurrences() {
        let cal = calendar()
        let meeting = makeScheduledMeeting(hour: 10, minute: 0, recurrence: .daily, enabled: false)
        let range = DateInterval(
            start: localDate(year: 2026, month: 9, day: 14, calendar: cal),
            end: localDate(year: 2026, month: 9, day: 21, calendar: cal)
        )

        let occurrences = OccurrenceEngine.occurrences(for: meeting, in: range, calendar: cal)

        XCTAssertTrue(occurrences.isEmpty)
    }

    func testQuickRoomProducesNoOccurrences() {
        let cal = calendar()
        let quickRoom = Meeting(
            name: "Командная комната",
            url: URL(string: "https://telemost.yandex.ru/j/111")!,
            service: .yandexTelemost,
            type: .quickRoom
        )
        let range = DateInterval(
            start: localDate(year: 2026, month: 9, day: 14, calendar: cal),
            end: localDate(year: 2026, month: 9, day: 21, calendar: cal)
        )

        let occurrences = OccurrenceEngine.occurrences(for: quickRoom, in: range, calendar: cal)

        XCTAssertTrue(occurrences.isEmpty)
    }

    // MARK: - Range boundaries (half-open interval)

    func testRangeExcludesExactEndBoundary() {
        let cal = calendar()
        let meeting = makeScheduledMeeting(hour: 10, minute: 0, recurrence: .daily)
        let exactStart = localDate(year: 2026, month: 9, day: 14, hour: 10, calendar: cal)
        // Диапазон заканчивается РОВНО в момент начала встречи — она не
        // должна попасть в результат (полуоткрытый интервал).
        let range = DateInterval(
            start: localDate(year: 2026, month: 9, day: 14, calendar: cal),
            end: exactStart
        )

        let occurrences = OccurrenceEngine.occurrences(for: meeting, in: range, calendar: cal)

        XCTAssertTrue(occurrences.isEmpty)
    }

    func testRangeIncludesExactStartBoundary() {
        let cal = calendar()
        let meeting = makeScheduledMeeting(hour: 10, minute: 0, recurrence: .daily)
        let exactStart = localDate(year: 2026, month: 9, day: 14, hour: 10, calendar: cal)
        // Диапазон начинается РОВНО в момент начала встречи — она должна
        // попасть в результат (начало интервала включительно).
        let range = DateInterval(
            start: exactStart,
            end: localDate(year: 2026, month: 9, day: 15, calendar: cal)
        )

        let occurrences = OccurrenceEngine.occurrences(for: meeting, in: range, calendar: cal)

        XCTAssertEqual(occurrences.count, 1)
        XCTAssertEqual(occurrences.first?.startDate, exactStart)
    }

    // MARK: - Month boundary

    func testMonthBoundaryDailyRecurrence() {
        let cal = calendar()
        let meeting = makeScheduledMeeting(hour: 10, minute: 0, recurrence: .daily)
        // 30, 31 января и 1, 2, 3 февраля — 5 дней через границу месяца.
        let range = DateInterval(
            start: localDate(year: 2026, month: 1, day: 30, calendar: cal),
            end: localDate(year: 2026, month: 2, day: 4, calendar: cal)
        )

        let occurrences = OccurrenceEngine.occurrences(for: meeting, in: range, calendar: cal)

        XCTAssertEqual(occurrences.count, 5)
        let expectedDays: [(Int, Int)] = [(1, 30), (1, 31), (2, 1), (2, 2), (2, 3)]
        for (occurrence, expected) in zip(occurrences, expectedDays) {
            let month = cal.component(.month, from: occurrence.startDate)
            let day = cal.component(.day, from: occurrence.startDate)
            XCTAssertEqual(month, expected.0)
            XCTAssertEqual(day, expected.1)
        }
    }

    // MARK: - DST transitions

    func testDSTSpringForwardKeepsWallClockTime() {
        // В США переход на летнее время в 2024 году — 10 марта, стрелки
        // переводятся с 02:00 на 03:00. Встреча в 10:00 должна остаться
        // в 10:00 по местному времени и в день перехода, и после него.
        let cal = calendar(timeZoneIdentifier: "America/Los_Angeles")
        let meeting = makeScheduledMeeting(hour: 10, minute: 0, recurrence: .daily)
        let range = DateInterval(
            start: localDate(year: 2024, month: 3, day: 9, calendar: cal),
            end: localDate(year: 2024, month: 3, day: 12, calendar: cal)
        )

        let occurrences = OccurrenceEngine.occurrences(for: meeting, in: range, calendar: cal)

        XCTAssertEqual(occurrences.count, 3)
        for occurrence in occurrences {
            XCTAssertEqual(cal.component(.hour, from: occurrence.startDate), 10)
            XCTAssertEqual(cal.component(.minute, from: occurrence.startDate), 0)
        }
    }

    func testDSTFallBackKeepsWallClockTime() {
        // Переход на зимнее время в 2024 году — 3 ноября, стрелки
        // переводятся с 02:00 на 01:00. Встреча в 10:00 не должна
        // задвоиться или пропасть.
        let cal = calendar(timeZoneIdentifier: "America/Los_Angeles")
        let meeting = makeScheduledMeeting(hour: 10, minute: 0, recurrence: .daily)
        let range = DateInterval(
            start: localDate(year: 2024, month: 11, day: 2, calendar: cal),
            end: localDate(year: 2024, month: 11, day: 5, calendar: cal)
        )

        let occurrences = OccurrenceEngine.occurrences(for: meeting, in: range, calendar: cal)

        XCTAssertEqual(occurrences.count, 3)
        for occurrence in occurrences {
            XCTAssertEqual(cal.component(.hour, from: occurrence.startDate), 10)
            XCTAssertEqual(cal.component(.minute, from: occurrence.startDate), 0)
        }
    }

    // MARK: - Multiple meetings

    func testMultipleMeetingsMergedAndSortedByStartTime() {
        let cal = calendar()
        let earlyMeeting = makeScheduledMeeting(name: "Daily", hour: 10, minute: 0, recurrence: .daily)
        let lateMeeting = makeScheduledMeeting(name: "Design Review", hour: 17, minute: 0, recurrence: .daily)
        let range = DateInterval(
            start: localDate(year: 2026, month: 9, day: 14, calendar: cal),
            end: localDate(year: 2026, month: 9, day: 15, calendar: cal)
        )

        let occurrences = OccurrenceEngine.occurrences(
            for: [lateMeeting, earlyMeeting],
            in: range,
            calendar: cal
        )

        XCTAssertEqual(occurrences.count, 2)
        XCTAssertEqual(occurrences.first?.meeting.name, "Daily")
        XCTAssertEqual(occurrences.last?.meeting.name, "Design Review")
    }

    // MARK: - Skip Today exceptions

    func testSkippedExceptionExcludesOnlyThatDay() {
        let cal = calendar()
        let meeting = makeScheduledMeeting(hour: 10, minute: 0, recurrence: .daily)
        let range = DateInterval(
            start: localDate(year: 2026, month: 9, day: 14, calendar: cal),
            end: localDate(year: 2026, month: 9, day: 19, calendar: cal) // 14..18, 5 дней
        )
        let skippedDay = localDate(year: 2026, month: 9, day: 16, hour: 10, calendar: cal)
        let exception = MeetingOccurrenceException(meetingID: meeting.id, date: skippedDay, isSkipped: true, calendar: cal)

        let occurrences = OccurrenceEngine.occurrences(for: meeting, in: range, exceptions: [exception], calendar: cal)

        XCTAssertEqual(occurrences.count, 4)
        let days = occurrences.map { cal.component(.day, from: $0.startDate) }
        XCTAssertFalse(days.contains(16))
        XCTAssertTrue(days.contains(14))
        XCTAssertTrue(days.contains(15))
        XCTAssertTrue(days.contains(17))
        XCTAssertTrue(days.contains(18))
    }

    func testExceptionForDifferentMeetingDoesNotAffectThisOne() {
        let cal = calendar()
        let meeting = makeScheduledMeeting(hour: 10, minute: 0, recurrence: .daily)
        let range = DateInterval(
            start: localDate(year: 2026, month: 9, day: 14, calendar: cal),
            end: localDate(year: 2026, month: 9, day: 16, calendar: cal)
        )
        let unrelatedException = MeetingOccurrenceException(
            meetingID: UUID(),
            date: localDate(year: 2026, month: 9, day: 14, hour: 10, calendar: cal),
            isSkipped: true,
            calendar: cal
        )

        let occurrences = OccurrenceEngine.occurrences(for: meeting, in: range, exceptions: [unrelatedException], calendar: cal)

        XCTAssertEqual(occurrences.count, 2)
    }

    func testNonSkippedExceptionDoesNotExcludeDay() {
        let cal = calendar()
        let meeting = makeScheduledMeeting(hour: 10, minute: 0, recurrence: .daily)
        let range = DateInterval(
            start: localDate(year: 2026, month: 9, day: 14, calendar: cal),
            end: localDate(year: 2026, month: 9, day: 15, calendar: cal)
        )
        let exception = MeetingOccurrenceException(
            meetingID: meeting.id,
            date: localDate(year: 2026, month: 9, day: 14, hour: 10, calendar: cal),
            isSkipped: false,
            calendar: cal
        )

        let occurrences = OccurrenceEngine.occurrences(for: meeting, in: range, exceptions: [exception], calendar: cal)

        XCTAssertEqual(occurrences.count, 1)
    }
}
