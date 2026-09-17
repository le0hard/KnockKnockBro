import XCTest
@testable import KnockKnockBro

final class ImportExportServiceTests: XCTestCase {

    // MARK: - Helpers

    private func makeQuickRoom(name: String = "Командная комната", id: UUID = UUID()) -> Meeting {
        Meeting(
            id: id,
            name: name,
            url: URL(string: "https://telemost.yandex.ru/j/111")!,
            service: .yandexTelemost,
            type: .quickRoom
        )
    }

    private func makeScheduledMeeting(
        name: String = "Daily", id: UUID = UUID(),
        hour: Int = 10, minute: Int = 0,
        recurrence: Recurrence = .daily
    ) -> Meeting {
        Meeting(
            id: id,
            name: name,
            url: URL(string: "https://telemost.yandex.ru/j/1")!,
            service: .yandexTelemost,
            type: .scheduled,
            schedule: MeetingSchedule(hour: hour, minute: minute, recurrence: recurrence)
        )
    }

    // MARK: - Export

    func testExportProducesDecodableRoundTrip() throws {
        let meetings = [makeQuickRoom(), makeScheduledMeeting()]
        let exceptions = [MeetingOccurrenceException(meetingID: meetings[1].id, date: Date(), isSkipped: true)]

        let data = try ImportExportService.export(meetings: meetings, exceptions: exceptions)
        let result = ImportExportService.validate(data: data)

        switch result {
        case .success(let validated):
            XCTAssertEqual(validated.meetings.count, 2)
            XCTAssertEqual(validated.exceptions.count, 1)
        case .failure(let error):
            XCTFail("Экспортированный файл должен проходить собственную валидацию: \(error)")
        }
    }

    func testExportIncludesCurrentFormatVersion() throws {
        let data = try ImportExportService.export(meetings: [], exceptions: [])
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["formatVersion"] as? Int, MeetingStore.currentFormatVersion)
    }

    // MARK: - Malformed JSON

    func testRejectsMalformedJSON() {
        let data = Data("{ this is not valid json".utf8)
        let result = ImportExportService.validate(data: data)

        XCTAssertEqual(result.failureError, .malformedJSON)
    }

    // MARK: - Format version

    func testRejectsUnsupportedFormatVersion() {
        let json = """
        { "formatVersion": 999, "meetings": [] }
        """
        let result = ImportExportService.validate(data: Data(json.utf8))

        XCTAssertEqual(result.failureError, .unsupportedFormatVersion(found: 999, supported: MeetingStore.currentFormatVersion))
    }

    // MARK: - Valid cases

    func testAcceptsValidQuickRoomOnly() throws {
        let data = try ImportExportService.export(meetings: [makeQuickRoom()], exceptions: [])
        let result = ImportExportService.validate(data: data)

        XCTAssertTrue(result.isSuccess)
    }

    func testAcceptsValidScheduledMeetingWithAllRecurrenceKinds() throws {
        let meetings = [
            makeScheduledMeeting(name: "Daily", recurrence: .daily),
            makeScheduledMeeting(name: "Weekdays", recurrence: .weekdays),
            makeScheduledMeeting(name: "Weekly", recurrence: .weekly(.monday)),
            makeScheduledMeeting(name: "Custom", recurrence: .customDays([.monday, .friday])),
        ]
        let data = try ImportExportService.export(meetings: meetings, exceptions: [])
        let result = ImportExportService.validate(data: data)

        XCTAssertTrue(result.isSuccess)
    }

    // MARK: - Invalid URL

    func testRejectsMeetingWithURLMissingScheme() throws {
        // Строим JSON вручную, так как штатный `Meeting` инициализатор
        // принимает только валидный `URL`, а нам нужно эмулировать файл,
        // отредактированный вручную с некорректным значением.
        let meetingID = UUID()
        let json = """
        {
          "formatVersion": 1,
          "meetings": [{
            "id": "\(meetingID.uuidString)",
            "name": "Битая ссылка",
            "url": "not-a-valid-url",
            "service": { "type": "unknown" },
            "type": "quickRoom",
            "enabled": true,
            "notifications": []
          }]
        }
        """
        let result = ImportExportService.validate(data: Data(json.utf8))

        // "not-a-valid-url" технически парсится как относительный URL без
        // scheme/host, поэтому должен быть отклонён нашей проверкой.
        XCTAssertEqual(result.failureError, .invalidURL(meetingName: "Битая ссылка"))
    }

    // MARK: - Missing schedule

    func testRejectsScheduledMeetingWithoutSchedule() throws {
        let meetingID = UUID()
        let json = """
        {
          "formatVersion": 1,
          "meetings": [{
            "id": "\(meetingID.uuidString)",
            "name": "Без расписания",
            "url": "https://telemost.yandex.ru/j/1",
            "service": { "type": "yandexTelemost" },
            "type": "scheduled",
            "enabled": true,
            "notifications": []
          }]
        }
        """
        let result = ImportExportService.validate(data: Data(json.utf8))

        XCTAssertEqual(result.failureError, .missingScheduleForScheduledMeeting(meetingName: "Без расписания"))
    }

    // MARK: - Invalid schedule time

    func testRejectsInvalidScheduleHour() {
        let meeting = makeScheduledMeeting(hour: 25, minute: 0)
        let json = try! ImportExportService.export(meetings: [meeting], exceptions: [])
        let result = ImportExportService.validate(data: json)

        XCTAssertEqual(result.failureError, .invalidScheduleTime(meetingName: "Daily"))
    }

    func testRejectsInvalidScheduleMinute() {
        let meeting = makeScheduledMeeting(hour: 10, minute: 75)
        let json = try! ImportExportService.export(meetings: [meeting], exceptions: [])
        let result = ImportExportService.validate(data: json)

        XCTAssertEqual(result.failureError, .invalidScheduleTime(meetingName: "Daily"))
    }

    // MARK: - Empty custom days

    func testRejectsEmptyCustomDaysRecurrence() {
        let meeting = makeScheduledMeeting(recurrence: .customDays([]))
        let json = try! ImportExportService.export(meetings: [meeting], exceptions: [])
        let result = ImportExportService.validate(data: json)

        XCTAssertEqual(result.failureError, .emptyCustomDaysRecurrence(meetingName: "Daily"))
    }

    // MARK: - Duplicate IDs

    func testRejectsDuplicateMeetingIDs() {
        let sharedID = UUID()
        let meetings = [
            makeQuickRoom(name: "Первая", id: sharedID),
            makeQuickRoom(name: "Вторая", id: sharedID),
        ]
        let json = try! ImportExportService.export(meetings: meetings, exceptions: [])
        let result = ImportExportService.validate(data: json)

        XCTAssertEqual(result.failureError, .duplicateMeetingID(meetingName: "Вторая"))
    }

    // MARK: - Orphaned exceptions

    func testRejectsExceptionReferencingUnknownMeeting() {
        let meeting = makeScheduledMeeting()
        let orphanException = MeetingOccurrenceException(meetingID: UUID(), date: Date(), isSkipped: true)
        let json = try! ImportExportService.export(meetings: [meeting], exceptions: [orphanException])
        let result = ImportExportService.validate(data: json)

        XCTAssertEqual(result.failureError, .exceptionReferencesUnknownMeeting)
    }

    func testAcceptsExceptionReferencingKnownMeeting() {
        let meeting = makeScheduledMeeting()
        let validException = MeetingOccurrenceException(meetingID: meeting.id, date: Date(), isSkipped: true)
        let json = try! ImportExportService.export(meetings: [meeting], exceptions: [validException])
        let result = ImportExportService.validate(data: json)

        XCTAssertTrue(result.isSuccess)
    }

    // MARK: - Atomicity: invalid entry anywhere rejects the whole file

    func testRejectsWholeFileWhenAnySingleMeetingIsInvalid() {
        let validMeeting = makeScheduledMeeting(name: "Valid", hour: 10, minute: 0)
        let invalidMeeting = makeScheduledMeeting(name: "Invalid", hour: 30, minute: 0)
        let json = try! ImportExportService.export(meetings: [validMeeting, invalidMeeting], exceptions: [])
        let result = ImportExportService.validate(data: json)

        XCTAssertFalse(result.isSuccess, "Один некорректный элемент должен отклонять весь файл целиком")
    }
}

// MARK: - Test helpers

private extension Result where Success == ValidatedImport, Failure == ImportValidationError {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    var failureError: ImportValidationError? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
