import XCTest
@testable import KnockKnockBro

/// Разовые встречи (v0.4.0): модель даты, JSON, разворачивание в
/// экземпляры, автоудаление, импорт формата 1 и 2.
final class OneTimeMeetingTests: XCTestCase {

    // MARK: - Helpers

    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
        return calendar
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func makeOneTimeMeeting(
        name: String = "Созвон с заказчиком",
        day: CalendarDay = CalendarDay(year: 2026, month: 10, day: 5),
        hour: Int = 10, minute: Int = 0,
        autoDelete: Bool = false
    ) -> Meeting {
        Meeting(
            name: name,
            url: URL(string: "https://telemost.yandex.ru/j/1")!,
            service: .yandexTelemost,
            type: .scheduled,
            schedule: MeetingSchedule(hour: hour, minute: minute, recurrence: .once(day, autoDelete: autoDelete))
        )
    }

    private func makeTempStore() throws -> (MeetingStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KnockKnockBroTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("meetings.json")
        return (MeetingStore(fileURL: url), directory)
    }

    // MARK: - CalendarDay

    func testCalendarDayISOStringRoundTrip() {
        let day = CalendarDay(year: 2026, month: 3, day: 7)
        XCTAssertEqual(day.isoString, "2026-03-07")
        XCTAssertEqual(CalendarDay(isoString: "2026-03-07"), day)
    }

    func testCalendarDayRejectsMalformedStrings() {
        XCTAssertNil(CalendarDay(isoString: "2026-3-7"))
        XCTAssertNil(CalendarDay(isoString: "07.03.2026"))
        XCTAssertNil(CalendarDay(isoString: "2026-03-07T10:00"))
        XCTAssertNil(CalendarDay(isoString: ""))
    }

    func testCalendarDayValidity() {
        let cal = calendar()
        XCTAssertTrue(CalendarDay(year: 2028, month: 2, day: 29).isValid(in: cal))
        XCTAssertFalse(CalendarDay(year: 2026, month: 2, day: 30).isValid(in: cal))
        XCTAssertFalse(CalendarDay(year: 2026, month: 13, day: 1).isValid(in: cal))
    }

    // MARK: - Codable

    func testOnceRecurrenceEncodesHumanReadableDate() throws {
        let meeting = makeOneTimeMeeting(autoDelete: true)
        let data = try JSONEncoder().encode(meeting)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let schedule = json?["schedule"] as? [String: Any]
        let recurrence = schedule?["recurrence"] as? [String: Any]

        XCTAssertEqual(recurrence?["type"] as? String, "once")
        XCTAssertEqual(recurrence?["date"] as? String, "2026-10-05")
        XCTAssertEqual(recurrence?["autoDelete"] as? Bool, true)

        let decoded = try JSONDecoder().decode(Meeting.self, from: data)
        XCTAssertEqual(decoded, meeting)
    }

    // MARK: - OccurrenceEngine

    func testOnceProducesExactlyOneOccurrenceOnItsDay() {
        let cal = calendar()
        let meeting = makeOneTimeMeeting()
        let range = DateInterval(
            start: date(year: 2026, month: 10, day: 1, calendar: cal),
            end: date(year: 2026, month: 10, day: 31, calendar: cal)
        )

        let occurrences = OccurrenceEngine.occurrences(for: meeting, in: range, calendar: cal)

        XCTAssertEqual(occurrences.count, 1)
        XCTAssertEqual(occurrences.first?.startDate, date(year: 2026, month: 10, day: 5, hour: 10, calendar: cal))
    }

    func testOnceProducesNothingOutsideItsDay() {
        let cal = calendar()
        let meeting = makeOneTimeMeeting()
        let range = DateInterval(
            start: date(year: 2026, month: 10, day: 6, calendar: cal),
            end: date(year: 2026, month: 11, day: 6, calendar: cal)
        )

        XCTAssertTrue(OccurrenceEngine.occurrences(for: meeting, in: range, calendar: cal).isEmpty)
    }

    // MARK: - Past

    func testIsPastOneTimeMeetingOnlyAfterItsDay() {
        let cal = calendar()
        let meeting = makeOneTimeMeeting()

        // В тот же день, уже после начала — ещё не "прошедшая".
        XCTAssertFalse(meeting.isPastOneTimeMeeting(now: date(year: 2026, month: 10, day: 5, hour: 23, calendar: cal), calendar: cal))
        XCTAssertTrue(meeting.isPastOneTimeMeeting(now: date(year: 2026, month: 10, day: 6, hour: 0, minute: 1, calendar: cal), calendar: cal))
    }

    // MARK: - Автоудаление

    func testAutoDeleteRemovesOnlyAfterOneHour() throws {
        let cal = calendar()
        let (store, directory) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let meeting = makeOneTimeMeeting(autoDelete: true)
        store.add(meeting)

        let removedEarly = store.deleteExpiredOneTimeMeetings(
            now: date(year: 2026, month: 10, day: 5, hour: 10, minute: 59, calendar: cal), calendar: cal
        )
        XCTAssertEqual(removedEarly, 0)
        XCTAssertEqual(store.meetings.count, 1)

        let removed = store.deleteExpiredOneTimeMeetings(
            now: date(year: 2026, month: 10, day: 5, hour: 11, minute: 0, calendar: cal), calendar: cal
        )
        XCTAssertEqual(removed, 1)
        XCTAssertTrue(store.meetings.isEmpty)
    }

    func testWithoutAutoDeleteMeetingIsKept() throws {
        let cal = calendar()
        let (store, directory) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        store.add(makeOneTimeMeeting(autoDelete: false))
        let removed = store.deleteExpiredOneTimeMeetings(
            now: date(year: 2027, month: 1, day: 1, calendar: cal), calendar: cal
        )

        XCTAssertEqual(removed, 0)
        XCTAssertEqual(store.meetings.count, 1)
    }

    func testAutoDeleteRemovesExceptionsToo() throws {
        let cal = calendar()
        let (store, directory) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let meeting = makeOneTimeMeeting(autoDelete: true)
        store.add(meeting)
        store.toggleSkip(meetingID: meeting.id, on: date(year: 2026, month: 10, day: 5, hour: 10, calendar: cal), calendar: cal)
        XCTAssertEqual(store.exceptions.count, 1)

        store.deleteExpiredOneTimeMeetings(now: date(year: 2026, month: 10, day: 6, calendar: cal), calendar: cal)

        XCTAssertTrue(store.exceptions.isEmpty)
    }

    // MARK: - Импорт

    func testImportAcceptsFormatVersion1() {
        let json = """
        { "formatVersion": 1, "meetings": [] }
        """
        let result = ImportExportService.validate(data: Data(json.utf8))
        if case .failure(let error) = result {
            XCTFail("Формат 1 должен по-прежнему импортироваться: \(error)")
        }
    }

    func testExportUsesFormatVersion2AndRoundTripsOneTimeMeeting() throws {
        let meeting = makeOneTimeMeeting(autoDelete: true)
        let data = try ImportExportService.export(meetings: [meeting], exceptions: [])
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["formatVersion"] as? Int, 2)

        switch ImportExportService.validate(data: data) {
        case .success(let validated):
            XCTAssertEqual(validated.meetings, [meeting])
        case .failure(let error):
            XCTFail("Экспорт с разовой встречей должен проходить валидацию: \(error)")
        }
    }

    func testImportRejectsNonexistentOneTimeDate() {
        let json = """
        {
          "formatVersion": 2,
          "meetings": [{
            "id": "\(UUID().uuidString)",
            "name": "Призрак",
            "url": "https://telemost.yandex.ru/j/1",
            "service": { "type": "yandexTelemost" },
            "type": "scheduled",
            "enabled": true,
            "notifications": [],
            "schedule": { "hour": 10, "minute": 0, "recurrence": { "type": "once", "date": "2026-02-30", "autoDelete": false } }
          }]
        }
        """
        let result = ImportExportService.validate(data: Data(json.utf8))
        guard case .failure(let error) = result else {
            return XCTFail("30 февраля не должно импортироваться")
        }
        XCTAssertEqual(error, .invalidOneTimeDate(meetingName: "Призрак"))
    }
}
