import XCTest
@testable import KnockKnockBro

/// Учёт подключения (v0.5.0): окно засчитывания, отметка в хранилище и её
/// влияние на Auto Join и промпт после пробуждения.
final class JoinTrackingTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KnockKnockBroTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
        return calendar
    }

    private func date(hour: Int, minute: Int = 0, day: Int = 5, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func makeDaily(autoJoin: Bool = false) -> Meeting {
        Meeting(
            name: "Daily",
            url: URL(string: "https://telemost.yandex.ru/j/1")!,
            service: .yandexTelemost,
            type: .scheduled,
            schedule: MeetingSchedule(hour: 10, minute: 0, recurrence: .daily),
            autoJoin: autoJoin ? AutoJoinSettings(isEnabled: true, countdownOverride: 10) : nil
        )
    }

    private func makeStore() -> MeetingStore {
        MeetingStore(fileURL: tempDirectory.appendingPathComponent("meetings.json"))
    }

    // MARK: - Окно засчитывания

    func testClickTooEarlyDoesNotCount() {
        let cal = calendar()
        XCTAssertFalse(JoinTracking.countsAsJoin(
            occurrenceStart: date(hour: 10, calendar: cal), now: date(hour: 9, minute: 44, calendar: cal),
            windowMinutes: 15, calendar: cal
        ))
    }

    func testClickInsideWindowCounts() {
        let cal = calendar()
        XCTAssertTrue(JoinTracking.countsAsJoin(
            occurrenceStart: date(hour: 10, calendar: cal), now: date(hour: 9, minute: 45, calendar: cal),
            windowMinutes: 15, calendar: cal
        ))
    }

    func testLateClickSameDayCounts() {
        let cal = calendar()
        XCTAssertTrue(JoinTracking.countsAsJoin(
            occurrenceStart: date(hour: 10, calendar: cal), now: date(hour: 23, minute: 30, calendar: cal),
            windowMinutes: 15, calendar: cal
        ))
    }

    func testClickNextDayDoesNotCount() {
        let cal = calendar()
        XCTAssertFalse(JoinTracking.countsAsJoin(
            occurrenceStart: date(hour: 10, calendar: cal), now: date(hour: 9, day: 6, calendar: cal),
            windowMinutes: 15, calendar: cal
        ))
    }

    func testZeroWindowCountsOnlyFromStart() {
        let cal = calendar()
        XCTAssertFalse(JoinTracking.countsAsJoin(
            occurrenceStart: date(hour: 10, calendar: cal), now: date(hour: 9, minute: 59, calendar: cal),
            windowMinutes: 0, calendar: cal
        ))
        XCTAssertTrue(JoinTracking.countsAsJoin(
            occurrenceStart: date(hour: 10, calendar: cal), now: date(hour: 10, calendar: cal),
            windowMinutes: 0, calendar: cal
        ))
    }

    // MARK: - Хранилище

    func testRecordJoinMarksOnlyThatDay() {
        let cal = calendar()
        let store = makeStore()
        let meeting = makeDaily()
        store.add(meeting)

        let recorded = store.recordJoinIfEligible(
            meeting: meeting, windowMinutes: 15, now: date(hour: 9, minute: 50, calendar: cal), calendar: cal
        )

        XCTAssertTrue(recorded)
        XCTAssertTrue(store.isJoined(meetingID: meeting.id, on: date(hour: 10, calendar: cal), calendar: cal))
        XCTAssertFalse(store.isJoined(meetingID: meeting.id, on: date(hour: 10, day: 6, calendar: cal), calendar: cal))
        XCTAssertNotNil(meeting.schedule, "Правило повторения не меняется")
    }

    func testEarlyClickIsNotRecorded() {
        let cal = calendar()
        let store = makeStore()
        let meeting = makeDaily()
        store.add(meeting)

        let recorded = store.recordJoinIfEligible(
            meeting: meeting, windowMinutes: 15, now: date(hour: 8, calendar: cal), calendar: cal
        )

        XCTAssertFalse(recorded)
        XCTAssertTrue(store.exceptions.isEmpty)
    }

    func testQuickRoomIsNeverRecorded() {
        let store = makeStore()
        let room = Meeting(
            name: "Комната",
            url: URL(string: "https://telemost.yandex.ru/j/2")!,
            service: .yandexTelemost,
            type: .quickRoom
        )
        store.add(room)

        XCTAssertFalse(store.recordJoinIfEligible(meeting: room, windowMinutes: 15))
    }

    func testMarkJoinedKeepsOtherFlagsOfTheDay() {
        let cal = calendar()
        let store = makeStore()
        let meeting = makeDaily()
        store.add(meeting)
        let start = date(hour: 10, calendar: cal)

        store.cancelAutoJoin(meetingID: meeting.id, on: start, calendar: cal)
        store.markJoined(meetingID: meeting.id, on: start, calendar: cal)

        XCTAssertEqual(store.exceptions.count, 1)
        XCTAssertTrue(store.exceptions[0].autoJoinCancelled)
        XCTAssertTrue(store.exceptions[0].joined)
    }

    func testJoinedFlagSurvivesReload() {
        let cal = calendar()
        let url = tempDirectory.appendingPathComponent("meetings.json")
        let meeting = makeDaily()
        let store1 = MeetingStore(fileURL: url)
        store1.add(meeting)
        store1.markJoined(meetingID: meeting.id, on: date(hour: 10, calendar: cal), calendar: cal)

        let store2 = MeetingStore(fileURL: url)
        XCTAssertTrue(store2.isJoined(meetingID: meeting.id, on: date(hour: 10, calendar: cal), calendar: cal))
    }

    func testOldExceptionWithoutJoinedKeyDecodes() throws {
        let json = """
        { "id": "\(UUID().uuidString)", "meetingID": "\(UUID().uuidString)",
          "year": 2026, "month": 10, "day": 5, "isSkipped": false, "autoJoinCancelled": true }
        """
        let exception = try JSONDecoder().decode(MeetingOccurrenceException.self, from: Data(json.utf8))
        XCTAssertFalse(exception.joined)
    }

    // MARK: - Влияние на Auto Join и промпт после сна

    func testAutoJoinDoesNotTriggerForJoinedOccurrence() {
        let cal = calendar()
        let meeting = makeDaily(autoJoin: true)
        let now = date(hour: 9, minute: 59, calendar: cal).addingTimeInterval(55)
        let joined = MeetingOccurrenceException(meetingID: meeting.id, date: now, joined: true, calendar: cal)

        XCTAssertNotNil(AutoJoinService.occurrenceToTrigger(
            meetings: [meeting], exceptions: [], defaultCountdown: 10, now: now, calendar: cal
        ))
        XCTAssertNil(AutoJoinService.occurrenceToTrigger(
            meetings: [meeting], exceptions: [joined], defaultCountdown: 10, now: now, calendar: cal
        ))
    }

    func testMissedPromptSkipsJoinedOccurrence() {
        let cal = calendar()
        let meeting = makeDaily()
        let now = date(hour: 10, minute: 3, calendar: cal)
        let joined = MeetingOccurrenceException(meetingID: meeting.id, date: now, joined: true, calendar: cal)

        XCTAssertNotNil(WakeObserver.findMissedOccurrence(meetings: [meeting], exceptions: [], now: now, calendar: cal))
        XCTAssertNil(WakeObserver.findMissedOccurrence(meetings: [meeting], exceptions: [joined], now: now, calendar: cal))
    }
}
