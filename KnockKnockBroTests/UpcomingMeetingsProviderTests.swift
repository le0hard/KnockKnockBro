import XCTest
@testable import KnockKnockBro

final class UpcomingMeetingsProviderTests: XCTestCase {
    
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
    
    private func makeMeeting(
        name: String, hour: Int, minute: Int,
        recurrence: Recurrence = .daily, enabled: Bool = true
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
    
    func testTodayOccurrencesIncludesPastAndFutureOccurrencesOfSameDay() {
        let cal = calendar()
        let now = date(year: 2026, month: 9, day: 16, hour: 12, minute: 0, calendar: cal)
        let morning = makeMeeting(name: "Morning", hour: 9, minute: 0)
        let evening = makeMeeting(name: "Evening", hour: 18, minute: 0)
        
        let occurrences = UpcomingMeetingsProvider.todayOccurrences(
            meetings: [morning, evening], exceptions: [], now: now, calendar: cal
        )
        
        XCTAssertEqual(occurrences.count, 2)
        XCTAssertEqual(occurrences.first?.meeting.name, "Morning")
        XCTAssertEqual(occurrences.last?.meeting.name, "Evening")
    }
    
    func testTodayOccurrencesExcludesQuickRooms() {
        let cal = calendar()
        let now = date(year: 2026, month: 9, day: 16, hour: 12, minute: 0, calendar: cal)
        let quickRoom = Meeting(
            name: "Комната",
            url: URL(string: "https://telemost.yandex.ru/j/1")!,
            service: .yandexTelemost,
            type: .quickRoom
        )
        
        let occurrences = UpcomingMeetingsProvider.todayOccurrences(
            meetings: [quickRoom], exceptions: [], now: now, calendar: cal
        )
        
        XCTAssertTrue(occurrences.isEmpty)
    }
    
    func testNextUpcomingOccurrenceSkipsPastOccurrenceToday() {
        let cal = calendar()
        let now = date(year: 2026, month: 9, day: 16, hour: 12, minute: 0, calendar: cal)
        let pastToday = makeMeeting(name: "Past", hour: 9, minute: 0)
        let futureToday = makeMeeting(name: "Future", hour: 18, minute: 0)
        
        let next = UpcomingMeetingsProvider.nextUpcomingOccurrence(
            meetings: [pastToday, futureToday], exceptions: [], now: now, calendar: cal
        )
        
        XCTAssertEqual(next?.meeting.name, "Future")
    }
    
    func testNextUpcomingOccurrenceRespectsSkipException() {
        let cal = calendar()
        let now = date(year: 2026, month: 9, day: 16, hour: 8, minute: 0, calendar: cal)
        let meeting = makeMeeting(name: "Daily", hour: 9, minute: 0)
        let todayOccurrenceStart = date(year: 2026, month: 9, day: 16, hour: 9, minute: 0, calendar: cal)
        let exception = MeetingOccurrenceException(meetingID: meeting.id, date: todayOccurrenceStart, isSkipped: true, calendar: cal)
        
        let next = UpcomingMeetingsProvider.nextUpcomingOccurrence(
            meetings: [meeting], exceptions: [exception], now: now, calendar: cal
        )
        
        // Сегодняшний экземпляр пропущен — следующий должен быть уже завтра.
        XCTAssertNotNil(next)
        XCTAssertEqual(cal.component(.day, from: next!.startDate), 17)
    }
    
    func testNextUpcomingOccurrenceIgnoresDisabledMeeting() {
        let cal = calendar()
        let now = date(year: 2026, month: 9, day: 16, hour: 8, minute: 0, calendar: cal)
        let meeting = makeMeeting(name: "Disabled", hour: 9, minute: 0, enabled: false)
        
        let next = UpcomingMeetingsProvider.nextUpcomingOccurrence(
            meetings: [meeting], exceptions: [], now: now, calendar: cal
        )
        
        XCTAssertNil(next)
    }
    
    // MARK: - Formatting
    
    func testCompactRemainingLabelUnderAnHour() {
        let now = Date()
        let target = now.addingTimeInterval(12 * 60)
        XCTAssertEqual(UpcomingMeetingsProvider.compactRemainingLabel(from: now, to: target), "12m")
    }
    
    func testCompactRemainingLabelExactHour() {
        let now = Date()
        let target = now.addingTimeInterval(60 * 60)
        XCTAssertEqual(UpcomingMeetingsProvider.compactRemainingLabel(from: now, to: target), "1h")
    }
    
    func testCompactRemainingLabelHoursAndMinutes() {
        let now = Date()
        let target = now.addingTimeInterval(4 * 60 * 60 + 42 * 60)
        XCTAssertEqual(UpcomingMeetingsProvider.compactRemainingLabel(from: now, to: target), "4h 42m")
    }
    
    func testRelativeTimeDescriptionUnderAnHour() {
        let now = Date()
        let target = now.addingTimeInterval(12 * 60)
        XCTAssertEqual(UpcomingMeetingsProvider.relativeTimeDescription(from: now, to: target), "через 12 мин")
    }
    
    func testRelativeTimeDescriptionHoursAndMinutes() {
        let now = Date()
        let target = now.addingTimeInterval(4 * 60 * 60 + 42 * 60)
        XCTAssertEqual(UpcomingMeetingsProvider.relativeTimeDescription(from: now, to: target), "через 4 ч 42 мин")
    }
    
    // MARK: - nextOccurrenceToday (для лейбла Menu Bar)

    func testNextOccurrenceTodayIsNilWhenOnlyRemainingIsTomorrow() {
        let cal = calendar()
        // Встреча в 00:01, "сейчас" — 23:00 того же дня. Формально
        // ближайшая встреча — завтра в 00:01, но сегодняшнего отсчёта
        // быть не должно.
        let now = date(year: 2026, month: 9, day: 16, hour: 23, minute: 0, calendar: cal)
        let meeting = makeMeeting(name: "Midnight", hour: 0, minute: 1)

        let next = UpcomingMeetingsProvider.nextOccurrenceToday(
            meetings: [meeting], exceptions: [], now: now, calendar: cal
        )

        XCTAssertNil(next)
    }

    func testNextOccurrenceTodayReturnsFutureOccurrenceLaterToday() {
        let cal = calendar()
        let now = date(year: 2026, month: 9, day: 16, hour: 12, minute: 0, calendar: cal)
        let meeting = makeMeeting(name: "Evening", hour: 18, minute: 0)

        let next = UpcomingMeetingsProvider.nextOccurrenceToday(
            meetings: [meeting], exceptions: [], now: now, calendar: cal
        )

        XCTAssertEqual(next?.meeting.name, "Evening")
    }

    func testNextOccurrenceTodayIsNilWhenAllTodayOccurrencesArePast() {
        let cal = calendar()
        let now = date(year: 2026, month: 9, day: 16, hour: 20, minute: 0, calendar: cal)
        let meeting = makeMeeting(name: "Morning", hour: 9, minute: 0)

        let next = UpcomingMeetingsProvider.nextOccurrenceToday(
            meetings: [meeting], exceptions: [], now: now, calendar: cal
        )

        XCTAssertNil(next)
    }
    
}
