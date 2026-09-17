import XCTest
@testable import KnockKnockBro

final class AutoJoinServiceTests: XCTestCase {

    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
        return calendar
    }

    private func date(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int = 0, calendar: Calendar) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return calendar.date(from: components)!
    }

    private func makeMeeting(
        name: String = "Daily",
        hour: Int, minute: Int,
        enabled: Bool = true,
        autoJoinEnabled: Bool = true,
        countdownOverride: TimeInterval? = nil
    ) -> Meeting {
        Meeting(
            name: name,
            url: URL(string: "https://telemost.yandex.ru/j/1")!,
            service: .yandexTelemost,
            type: .scheduled,
            enabled: enabled,
            schedule: MeetingSchedule(hour: hour, minute: minute, recurrence: .daily),
            autoJoin: AutoJoinSettings(isEnabled: autoJoinEnabled, countdownOverride: countdownOverride)
        )
    }

    // MARK: - Basic trigger window

    func testTriggersWhenNowIsWithinCountdownWindow() {
        let cal = calendar()
        let meeting = makeMeeting(hour: 10, minute: 0, countdownOverride: 10)
        // Старт в 10:00:00, countdown 10 секунд — окно триггера [09:59:50, 10:00:00).
        let now = date(year: 2026, month: 9, day: 16, hour: 9, minute: 59, second: 55, calendar: cal)

        let result = AutoJoinService.occurrenceToTrigger(
            meetings: [meeting], exceptions: [], defaultCountdown: 10, now: now, calendar: cal
        )

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.meeting.name, "Daily")
    }

    func testDoesNotTriggerBeforeCountdownWindowStarts() {
        let cal = calendar()
        let meeting = makeMeeting(hour: 10, minute: 0, countdownOverride: 10)
        // За 30 секунд до старта — countdown ещё не должен идти (окно всего 10 сек).
        let now = date(year: 2026, month: 9, day: 16, hour: 9, minute: 59, second: 30, calendar: cal)

        let result = AutoJoinService.occurrenceToTrigger(
            meetings: [meeting], exceptions: [], defaultCountdown: 10, now: now, calendar: cal
        )

        XCTAssertNil(result)
    }

    func testDoesNotTriggerAtOrAfterStartTime() {
        let cal = calendar()
        let meeting = makeMeeting(hour: 10, minute: 0, countdownOverride: 10)
        // Ровно в момент старта — это уже зона Missed Meeting, не Auto Join.
        let now = date(year: 2026, month: 9, day: 16, hour: 10, minute: 0, second: 0, calendar: cal)

        let result = AutoJoinService.occurrenceToTrigger(
            meetings: [meeting], exceptions: [], defaultCountdown: 10, now: now, calendar: cal
        )

        XCTAssertNil(result)
    }

    // MARK: - Enable/Disable and Auto Join flag

    func testDoesNotTriggerWhenMeetingDisabled() {
        let cal = calendar()
        let meeting = makeMeeting(hour: 10, minute: 0, enabled: false, countdownOverride: 10)
        let now = date(year: 2026, month: 9, day: 16, hour: 9, minute: 59, second: 55, calendar: cal)

        let result = AutoJoinService.occurrenceToTrigger(
            meetings: [meeting], exceptions: [], defaultCountdown: 10, now: now, calendar: cal
        )

        XCTAssertNil(result)
    }

    func testDoesNotTriggerWhenAutoJoinDisabledOnMeeting() {
        let cal = calendar()
        let meeting = makeMeeting(hour: 10, minute: 0, autoJoinEnabled: false, countdownOverride: 10)
        let now = date(year: 2026, month: 9, day: 16, hour: 9, minute: 59, second: 55, calendar: cal)

        let result = AutoJoinService.occurrenceToTrigger(
            meetings: [meeting], exceptions: [], defaultCountdown: 10, now: now, calendar: cal
        )

        XCTAssertNil(result)
    }

    func testDoesNotTriggerWhenAutoJoinSettingsIsNil() {
        let cal = calendar()
        let meeting = Meeting(
            name: "No Auto Join",
            url: URL(string: "https://telemost.yandex.ru/j/1")!,
            service: .yandexTelemost,
            type: .scheduled,
            schedule: MeetingSchedule(hour: 10, minute: 0, recurrence: .daily),
            autoJoin: nil
        )
        let now = date(year: 2026, month: 9, day: 16, hour: 9, minute: 59, second: 55, calendar: cal)

        let result = AutoJoinService.occurrenceToTrigger(
            meetings: [meeting], exceptions: [], defaultCountdown: 10, now: now, calendar: cal
        )

        XCTAssertNil(result)
    }

    // MARK: - Exceptions

    func testDoesNotTriggerWhenSkippedToday() {
        let cal = calendar()
        let meeting = makeMeeting(hour: 10, minute: 0, countdownOverride: 10)
        let occurrenceStart = date(year: 2026, month: 9, day: 16, hour: 10, minute: 0, calendar: cal)
        let exception = MeetingOccurrenceException(meetingID: meeting.id, date: occurrenceStart, isSkipped: true, calendar: cal)
        let now = date(year: 2026, month: 9, day: 16, hour: 9, minute: 59, second: 55, calendar: cal)

        let result = AutoJoinService.occurrenceToTrigger(
            meetings: [meeting], exceptions: [exception], defaultCountdown: 10, now: now, calendar: cal
        )

        XCTAssertNil(result)
    }

    func testDoesNotTriggerWhenAutoJoinCancelledForToday() {
        let cal = calendar()
        let meeting = makeMeeting(hour: 10, minute: 0, countdownOverride: 10)
        let occurrenceStart = date(year: 2026, month: 9, day: 16, hour: 10, minute: 0, calendar: cal)
        let exception = MeetingOccurrenceException(meetingID: meeting.id, date: occurrenceStart, autoJoinCancelled: true, calendar: cal)
        let now = date(year: 2026, month: 9, day: 16, hour: 9, minute: 59, second: 55, calendar: cal)

        let result = AutoJoinService.occurrenceToTrigger(
            meetings: [meeting], exceptions: [exception], defaultCountdown: 10, now: now, calendar: cal
        )

        XCTAssertNil(result)
    }

    func testAutoJoinCancelledDoesNotAffectDifferentDay() {
        let cal = calendar()
        let meeting = makeMeeting(hour: 10, minute: 0, countdownOverride: 10)
        // Отмена была для ВЧЕРАШНЕГО дня — сегодняшний экземпляр не должен пострадать.
        let yesterday = date(year: 2026, month: 9, day: 15, hour: 10, minute: 0, calendar: cal)
        let exception = MeetingOccurrenceException(meetingID: meeting.id, date: yesterday, autoJoinCancelled: true, calendar: cal)
        let now = date(year: 2026, month: 9, day: 16, hour: 9, minute: 59, second: 55, calendar: cal)

        let result = AutoJoinService.occurrenceToTrigger(
            meetings: [meeting], exceptions: [exception], defaultCountdown: 10, now: now, calendar: cal
        )

        XCTAssertNotNil(result)
    }

    // MARK: - Already triggered

    func testDoesNotRetriggerAlreadyShownOccurrence() {
        let cal = calendar()
        let meeting = makeMeeting(hour: 10, minute: 0, countdownOverride: 10)
        let now = date(year: 2026, month: 9, day: 16, hour: 9, minute: 59, second: 55, calendar: cal)

        let first = AutoJoinService.occurrenceToTrigger(
            meetings: [meeting], exceptions: [], defaultCountdown: 10, now: now, calendar: cal
        )
        XCTAssertNotNil(first)

        let second = AutoJoinService.occurrenceToTrigger(
            meetings: [meeting], exceptions: [], defaultCountdown: 10,
            alreadyTriggeredOccurrenceIDs: [first!.id], now: now, calendar: cal
        )
        XCTAssertNil(second)
    }

    // MARK: - Countdown resolution

    func testUsesGlobalDefaultCountdownWhenNoOverride() {
        let cal = calendar()
        let meeting = makeMeeting(hour: 10, minute: 0, countdownOverride: nil)
        // Глобальный дефолт 30 секунд, но override отсутствует — окно [09:59:30, 10:00:00).
        let now = date(year: 2026, month: 9, day: 16, hour: 9, minute: 59, second: 45, calendar: cal)

        let result = AutoJoinService.occurrenceToTrigger(
            meetings: [meeting], exceptions: [], defaultCountdown: 30, now: now, calendar: cal
        )

        XCTAssertNotNil(result)
    }

    func testPerMeetingOverrideTakesPrecedenceOverGlobalDefault() {
        let cal = calendar()
        // Override 5 секунд, глобальный дефолт 60 — если бы override не применялся,
        // окно было бы намного шире и этот момент попал бы в него ошибочно широко.
        let meeting = makeMeeting(hour: 10, minute: 0, countdownOverride: 5)
        let now = date(year: 2026, month: 9, day: 16, hour: 9, minute: 59, second: 40, calendar: cal)

        let result = AutoJoinService.occurrenceToTrigger(
            meetings: [meeting], exceptions: [], defaultCountdown: 60, now: now, calendar: cal
        )

        XCTAssertNil(result, "За пределами 5-секундного override, несмотря на широкий глобальный дефолт")
    }

    func testResolvedCountdownPrefersOverride() {
        let meeting = makeMeeting(hour: 10, minute: 0, countdownOverride: 15)
        XCTAssertEqual(AutoJoinService.resolvedCountdown(for: meeting, defaultCountdown: 30), 15)
    }

    func testResolvedCountdownFallsBackToDefault() {
        let meeting = makeMeeting(hour: 10, minute: 0, countdownOverride: nil)
        XCTAssertEqual(AutoJoinService.resolvedCountdown(for: meeting, defaultCountdown: 30), 30)
    }

    // MARK: - Multiple candidates

    func testPicksEarliestAmongMultipleTriggerableCandidates() {
        let cal = calendar()
        let earlier = makeMeeting(name: "Earlier", hour: 10, minute: 0, countdownOverride: 30)
        let later = makeMeeting(name: "Later", hour: 10, minute: 5, countdownOverride: 30)
        // Оба в окне countdown (30 сек) относительно now.
        let now = date(year: 2026, month: 9, day: 16, hour: 9, minute: 59, second: 40, calendar: cal)

        let result = AutoJoinService.occurrenceToTrigger(
            meetings: [later, earlier], exceptions: [], defaultCountdown: 30, now: now, calendar: cal
        )

        XCTAssertEqual(result?.meeting.name, "Earlier")
    }
}
