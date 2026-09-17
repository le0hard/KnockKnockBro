import XCTest
@testable import KnockKnockBro

final class WakeObserverLogicTests: XCTestCase {

    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
        return calendar
    }

    private func date(year: Int, month: Int, day: Int, hour: Int, minute: Int, calendar: Calendar) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }

    private func makeMeeting(name: String, hour: Int, minute: Int, enabled: Bool = true) -> Meeting {
        Meeting(
            name: name,
            url: URL(string: "https://telemost.yandex.ru/j/1")!,
            service: .yandexTelemost,
            type: .scheduled,
            enabled: enabled,
            schedule: MeetingSchedule(hour: hour, minute: minute, recurrence: .daily)
        )
    }

    func testFindsRecentlyMissedMeeting() {
        let cal = calendar()
        // Встреча в 10:00, "проснулись" в 10:03 — типичный случай пропущенной из-за сна встречи.
        let meeting = makeMeeting(name: "Daily", hour: 10, minute: 0)
        let wakeTime = date(year: 2026, month: 9, day: 16, hour: 10, minute: 3, calendar: cal)

        let missed = WakeObserver.findMissedOccurrence(meetings: [meeting], exceptions: [], now: wakeTime, calendar: cal)

        XCTAssertNotNil(missed)
        XCTAssertEqual(missed?.meeting.name, "Daily")
    }

    func testIgnoresMeetingOutsideMissedWindow() {
        let cal = calendar()
        // Встреча в 10:00, "проснулись" в 10:25 — за пределами 10-минутного окна.
        let meeting = makeMeeting(name: "Daily", hour: 10, minute: 0)
        let wakeTime = date(year: 2026, month: 9, day: 16, hour: 10, minute: 25, calendar: cal)

        let missed = WakeObserver.findMissedOccurrence(meetings: [meeting], exceptions: [], now: wakeTime, calendar: cal)

        XCTAssertNil(missed)
    }

    func testIgnoresFutureMeeting() {
        let cal = calendar()
        // Встреча в 10:00, "проснулись" в 9:55 — она ещё не началась.
        let meeting = makeMeeting(name: "Daily", hour: 10, minute: 0)
        let wakeTime = date(year: 2026, month: 9, day: 16, hour: 9, minute: 55, calendar: cal)

        let missed = WakeObserver.findMissedOccurrence(meetings: [meeting], exceptions: [], now: wakeTime, calendar: cal)

        XCTAssertNil(missed)
    }

    func testIgnoresDisabledMeeting() {
        let cal = calendar()
        let meeting = makeMeeting(name: "Daily", hour: 10, minute: 0, enabled: false)
        let wakeTime = date(year: 2026, month: 9, day: 16, hour: 10, minute: 3, calendar: cal)

        let missed = WakeObserver.findMissedOccurrence(meetings: [meeting], exceptions: [], now: wakeTime, calendar: cal)

        XCTAssertNil(missed)
    }

    func testRespectsSkipTodayException() {
        let cal = calendar()
        let meeting = makeMeeting(name: "Daily", hour: 10, minute: 0)
        let occurrenceStart = date(year: 2026, month: 9, day: 16, hour: 10, minute: 0, calendar: cal)
        let exception = MeetingOccurrenceException(meetingID: meeting.id, date: occurrenceStart, isSkipped: true, calendar: cal)
        let wakeTime = date(year: 2026, month: 9, day: 16, hour: 10, minute: 3, calendar: cal)

        let missed = WakeObserver.findMissedOccurrence(meetings: [meeting], exceptions: [exception], now: wakeTime, calendar: cal)

        XCTAssertNil(missed)
    }

    func testIgnoresQuickRoom() {
        let cal = calendar()
        let quickRoom = Meeting(
            name: "Комната",
            url: URL(string: "https://telemost.yandex.ru/j/1")!,
            service: .yandexTelemost,
            type: .quickRoom
        )
        let wakeTime = date(year: 2026, month: 9, day: 16, hour: 10, minute: 3, calendar: cal)

        let missed = WakeObserver.findMissedOccurrence(meetings: [quickRoom], exceptions: [], now: wakeTime, calendar: cal)

        XCTAssertNil(missed)
    }

    func testPicksLatestWhenMultipleMissedMeetingsExist() {
        let cal = calendar()
        let earlier = makeMeeting(name: "Earlier", hour: 9, minute: 55)
        let later = makeMeeting(name: "Later", hour: 10, minute: 0)
        let wakeTime = date(year: 2026, month: 9, day: 16, hour: 10, minute: 3, calendar: cal)

        let missed = WakeObserver.findMissedOccurrence(meetings: [earlier, later], exceptions: [], now: wakeTime, calendar: cal)

        XCTAssertEqual(missed?.meeting.name, "Later")
    }
}
