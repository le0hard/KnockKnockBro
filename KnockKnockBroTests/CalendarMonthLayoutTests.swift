import XCTest
@testable import KnockKnockBro

final class CalendarMonthLayoutTests: XCTestCase {

    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
        return calendar
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func makeMeeting(name: String, hour: Int, recurrence: Recurrence) -> Meeting {
        Meeting(
            name: name,
            url: URL(string: "https://telemost.yandex.ru/j/1")!,
            service: .yandexTelemost,
            type: .scheduled,
            schedule: MeetingSchedule(hour: hour, minute: 0, recurrence: recurrence)
        )
    }

    // MARK: - Сетка месяца

    func testOctober2026StartsOnThursday() {
        let cal = calendar()
        let monthStart = date(year: 2026, month: 10, day: 1, calendar: cal)

        let cells = CalendarMonthLayout.cells(forMonthStarting: monthStart, calendar: cal)

        // Пн, Вт, Ср пустые; 1 октября — четверг.
        XCTAssertEqual(cells.prefix(3).filter { $0 == nil }.count, 3)
        XCTAssertEqual(cells[3], monthStart)
        XCTAssertEqual(cells.compactMap { $0 }.count, 31)
        XCTAssertEqual(cells.count % 7, 0)
        XCTAssertEqual(cells.count, 35)
    }

    func testMonthStartingOnMondayHasNoLeadingCells() {
        let cal = calendar()
        let monthStart = date(year: 2026, month: 6, day: 1, calendar: cal)

        let cells = CalendarMonthLayout.cells(forMonthStarting: monthStart, calendar: cal)

        XCTAssertEqual(cells.first, monthStart)
        XCTAssertEqual(cells.count, 35)
    }

    func testMonthStartingOnSundayHasSixLeadingCells() {
        let cal = calendar()
        let monthStart = date(year: 2026, month: 2, day: 1, calendar: cal)

        let cells = CalendarMonthLayout.cells(forMonthStarting: monthStart, calendar: cal)

        XCTAssertEqual(cells.prefix(6).filter { $0 == nil }.count, 6)
        XCTAssertEqual(cells[6], monthStart)
    }

    func testFebruary2027FitsExactlyFourWeeks() {
        let cal = calendar()
        let cells = CalendarMonthLayout.cells(forMonthStarting: date(year: 2027, month: 2, day: 1, calendar: cal), calendar: cal)
        XCTAssertEqual(cells.count, 28)
        XCTAssertFalse(cells.contains { $0 == nil })
    }

    func testMonthNavigationCrossesYearBoundary() {
        let cal = calendar()
        let december = date(year: 2026, month: 12, day: 1, calendar: cal)
        XCTAssertEqual(CalendarMonthLayout.month(byAdding: 1, to: december, calendar: cal), date(year: 2027, month: 1, day: 1, calendar: cal))
        XCTAssertEqual(CalendarMonthLayout.month(byAdding: -12, to: december, calendar: cal), date(year: 2025, month: 12, day: 1, calendar: cal))
    }

    // MARK: - Перенос выбранного дня при листании

    func testPreferredDayKeepsSameNumberWhenItExists() {
        let cal = calendar()
        let october = date(year: 2026, month: 10, day: 1, calendar: cal)
        XCTAssertEqual(CalendarMonthLayout.day(5, inMonthStarting: october, calendar: cal), date(year: 2026, month: 10, day: 5, calendar: cal))
    }

    func testPreferredDayClampsToEndOfShortMonth() {
        let cal = calendar()
        XCTAssertEqual(
            CalendarMonthLayout.day(31, inMonthStarting: date(year: 2027, month: 2, day: 1, calendar: cal), calendar: cal),
            date(year: 2027, month: 2, day: 28, calendar: cal)
        )
        XCTAssertEqual(
            CalendarMonthLayout.day(31, inMonthStarting: date(year: 2028, month: 2, day: 1, calendar: cal), calendar: cal),
            date(year: 2028, month: 2, day: 29, calendar: cal)
        )
        XCTAssertEqual(
            CalendarMonthLayout.day(31, inMonthStarting: date(year: 2026, month: 4, day: 1, calendar: cal), calendar: cal),
            date(year: 2026, month: 4, day: 30, calendar: cal)
        )
    }

    func testPreferredDayReturnsToOriginalNumberAfterShortMonth() {
        let cal = calendar()
        // 31 января → февраль (28) → март: снова 31-е, т.к. хранится
        // выбранное число, а не последняя показанная дата.
        XCTAssertEqual(
            CalendarMonthLayout.day(31, inMonthStarting: date(year: 2027, month: 3, day: 1, calendar: cal), calendar: cal),
            date(year: 2027, month: 3, day: 31, calendar: cal)
        )
    }

    // MARK: - Встречи по дням

    func testDaysWithMeetingsMarksWeeklyAndOneTimeMeetings() {
        let cal = calendar()
        let monthStart = date(year: 2026, month: 10, day: 1, calendar: cal)
        let weekly = makeMeeting(name: "Планёрка", hour: 10, recurrence: .weekly(.monday))
        let oneTime = makeMeeting(name: "Демо", hour: 15, recurrence: .once(CalendarDay(year: 2026, month: 10, day: 15), autoDelete: false))

        let days = CalendarMonthLayout.daysWithMeetings(meetings: [weekly, oneTime], exceptions: [], monthStart: monthStart, calendar: cal)

        // Понедельники октября 2026: 5, 12, 19, 26 + разовая 15-го.
        let expected = Set([5, 12, 15, 19, 26].map { CalendarDay(year: 2026, month: 10, day: $0) })
        XCTAssertEqual(days, expected)
    }

    func testSkippedDayHasNoDotButStaysInAgendaAsSkipped() {
        let cal = calendar()
        let monthStart = date(year: 2026, month: 10, day: 1, calendar: cal)
        let daily = makeMeeting(name: "Daily", hour: 10, recurrence: .daily)
        let skippedDate = date(year: 2026, month: 10, day: 7, hour: 10, calendar: cal)
        let exception = MeetingOccurrenceException(meetingID: daily.id, date: skippedDate, isSkipped: true, calendar: cal)

        let days = CalendarMonthLayout.daysWithMeetings(meetings: [daily], exceptions: [exception], monthStart: monthStart, calendar: cal)
        XCTAssertFalse(days.contains(CalendarDay(year: 2026, month: 10, day: 7)))
        XCTAssertEqual(days.count, 30)

        let agenda = CalendarMonthLayout.agenda(on: skippedDate, meetings: [daily], exceptions: [exception], calendar: cal)
        XCTAssertEqual(agenda.count, 1)
        XCTAssertEqual(agenda.first?.isSkipped, true)
    }

    func testAgendaIsSortedByStartTimeAndIgnoresQuickRooms() {
        let cal = calendar()
        let day = date(year: 2026, month: 10, day: 5, calendar: cal)
        let late = makeMeeting(name: "Вечер", hour: 18, recurrence: .daily)
        let early = makeMeeting(name: "Утро", hour: 9, recurrence: .daily)
        let quickRoom = Meeting(
            name: "Комната",
            url: URL(string: "https://telemost.yandex.ru/j/2")!,
            service: .yandexTelemost,
            type: .quickRoom
        )

        let agenda = CalendarMonthLayout.agenda(on: day, meetings: [late, quickRoom, early], exceptions: [], calendar: cal)

        XCTAssertEqual(agenda.map(\.occurrence.meeting.name), ["Утро", "Вечер"])
    }
}
