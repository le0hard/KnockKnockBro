import XCTest
@testable import KnockKnockBro

final class MeetingStoreTests: XCTestCase {

    private var tempFileURL: URL!

    override func setUpWithError() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KnockKnockBroTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        tempFileURL = directory.appendingPathComponent("meetings.json")
    }

    override func tearDownWithError() throws {
        let directory = tempFileURL.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: directory)
        tempFileURL = nil
    }

    private func makeQuickRoom(name: String = "Командная комната") -> Meeting {
        Meeting(
            name: name,
            url: URL(string: "https://telemost.yandex.ru/j/111")!,
            service: .yandexTelemost,
            type: .quickRoom
        )
    }

    private func makeScheduledDailyMeeting() -> Meeting {
        Meeting(
            name: "Daily",
            url: URL(string: "https://telemost.yandex.ru/j/1")!,
            service: .yandexTelemost,
            type: .scheduled,
            schedule: MeetingSchedule(hour: 10, minute: 0, recurrence: .daily)
        )
    }

    func testFirstLaunchWithNoFileStartsEmpty() {
        let store = MeetingStore(fileURL: tempFileURL)
        XCTAssertTrue(store.meetings.isEmpty)
        XCTAssertNil(store.lastLoadError)
    }

    func testAddPersistsAcrossInstances() {
        let store1 = MeetingStore(fileURL: tempFileURL)
        let meeting = makeQuickRoom()
        store1.add(meeting)

        let store2 = MeetingStore(fileURL: tempFileURL)
        XCTAssertEqual(store2.meetings.count, 1)
        XCTAssertEqual(store2.meetings.first, meeting)
    }

    func testUpdateChangesExistingMeeting() {
        let store = MeetingStore(fileURL: tempFileURL)
        var meeting = makeQuickRoom()
        store.add(meeting)

        meeting.name = "Обновлённое имя"
        store.update(meeting)

        XCTAssertEqual(store.meetings.first?.name, "Обновлённое имя")

        let reloaded = MeetingStore(fileURL: tempFileURL)
        XCTAssertEqual(reloaded.meetings.first?.name, "Обновлённое имя")
    }

    func testUpdateWithUnknownIDIsNoOp() {
        let store = MeetingStore(fileURL: tempFileURL)
        store.add(makeQuickRoom())

        let unrelated = makeQuickRoom(name: "Не существующая встреча")
        store.update(unrelated)

        XCTAssertEqual(store.meetings.count, 1)
        XCTAssertNotEqual(store.meetings.first?.name, "Не существующая встреча")
    }

    func testDeleteRemovesMeeting() {
        let store = MeetingStore(fileURL: tempFileURL)
        let meeting = makeQuickRoom()
        store.add(meeting)
        XCTAssertEqual(store.meetings.count, 1)

        store.delete(id: meeting.id)
        XCTAssertTrue(store.meetings.isEmpty)

        let reloaded = MeetingStore(fileURL: tempFileURL)
        XCTAssertTrue(reloaded.meetings.isEmpty)
    }

    func testSetEnabledTogglesFlag() {
        let store = MeetingStore(fileURL: tempFileURL)
        let meeting = makeQuickRoom()
        store.add(meeting)
        XCTAssertTrue(store.meetings.first?.enabled ?? false)

        store.setEnabled(id: meeting.id, enabled: false)
        XCTAssertFalse(store.meetings.first?.enabled ?? true)
    }

    func testReplaceAllOverwritesEverything() {
        let store = MeetingStore(fileURL: tempFileURL)
        store.add(makeQuickRoom(name: "Первая"))
        store.add(makeQuickRoom(name: "Вторая"))
        XCTAssertEqual(store.meetings.count, 2)

        let newMeetings = [makeQuickRoom(name: "Импортированная")]
        store.replaceAll(meetings: newMeetings)

        XCTAssertEqual(store.meetings.count, 1)
        XCTAssertEqual(store.meetings.first?.name, "Импортированная")
    }

    func testReplaceAllAlsoReplacesExceptions() {
        let store = MeetingStore(fileURL: tempFileURL)
        let meeting = makeScheduledDailyMeeting()
        store.add(meeting)
        store.toggleSkip(meetingID: meeting.id)
        XCTAssertEqual(store.exceptions.count, 1)

        let newMeeting = makeScheduledDailyMeeting()
        let newException = MeetingOccurrenceException(meetingID: newMeeting.id, date: Date(), isSkipped: true)
        store.replaceAll(meetings: [newMeeting], exceptions: [newException])

        XCTAssertEqual(store.exceptions.count, 1)
        XCTAssertEqual(store.exceptions.first?.meetingID, newMeeting.id)
    }

    func testCorruptedFileDoesNotCrashAndStartsEmpty() throws {
        let directory = tempFileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "{ this is not valid json".write(to: tempFileURL, atomically: true, encoding: .utf8)

        let store = MeetingStore(fileURL: tempFileURL)

        XCTAssertTrue(store.meetings.isEmpty)
        XCTAssertNotNil(store.lastLoadError)
    }

    func testStoredFileUsesCurrentFormatVersion() throws {
        let store = MeetingStore(fileURL: tempFileURL)
        store.add(makeQuickRoom())

        let data = try Data(contentsOf: tempFileURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["formatVersion"] as? Int, MeetingStore.currentFormatVersion)
    }

    // MARK: - Skip Today

    func testToggleSkipAddsExceptionAndIsSkippedReturnsTrue() {
        let store = MeetingStore(fileURL: tempFileURL)
        let meeting = makeScheduledDailyMeeting()
        store.add(meeting)

        XCTAssertFalse(store.isSkipped(meetingID: meeting.id))

        store.toggleSkip(meetingID: meeting.id)

        XCTAssertTrue(store.isSkipped(meetingID: meeting.id))
        XCTAssertEqual(store.exceptions.count, 1)
    }

    func testToggleSkipTwiceRemovesException() {
        let store = MeetingStore(fileURL: tempFileURL)
        let meeting = makeScheduledDailyMeeting()
        store.add(meeting)

        store.toggleSkip(meetingID: meeting.id)
        store.toggleSkip(meetingID: meeting.id)

        XCTAssertFalse(store.isSkipped(meetingID: meeting.id))
        XCTAssertTrue(store.exceptions.isEmpty)
    }

    func testSkipExceptionPersistsAcrossInstances() {
        let store1 = MeetingStore(fileURL: tempFileURL)
        let meeting = makeScheduledDailyMeeting()
        store1.add(meeting)
        store1.toggleSkip(meetingID: meeting.id)

        let store2 = MeetingStore(fileURL: tempFileURL)
        XCTAssertTrue(store2.isSkipped(meetingID: meeting.id))
    }

    func testDeletingMeetingRemovesItsExceptions() {
        let store = MeetingStore(fileURL: tempFileURL)
        let meeting = makeScheduledDailyMeeting()
        store.add(meeting)
        store.toggleSkip(meetingID: meeting.id)
        XCTAssertEqual(store.exceptions.count, 1)

        store.delete(id: meeting.id)

        XCTAssertTrue(store.exceptions.isEmpty)
    }

    func testOldStorageFileWithoutExceptionsKeyLoadsSuccessfully() throws {
        let directory = tempFileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacyJSON = """
        {
          "formatVersion": 1,
          "meetings": []
        }
        """
        try legacyJSON.write(to: tempFileURL, atomically: true, encoding: .utf8)

        let store = MeetingStore(fileURL: tempFileURL)

        XCTAssertNil(store.lastLoadError)
        XCTAssertTrue(store.exceptions.isEmpty)
    }

    // MARK: - Auto Join cancellation

    func testCancelAutoJoinSetsFlag() {
        let store = MeetingStore(fileURL: tempFileURL)
        let meeting = makeScheduledDailyMeeting()
        store.add(meeting)

        XCTAssertFalse(store.isAutoJoinCancelled(meetingID: meeting.id))

        store.cancelAutoJoin(meetingID: meeting.id)

        XCTAssertTrue(store.isAutoJoinCancelled(meetingID: meeting.id))
    }

    func testCancelAutoJoinDoesNotAffectSkipToday() {
        let store = MeetingStore(fileURL: tempFileURL)
        let meeting = makeScheduledDailyMeeting()
        store.add(meeting)

        store.cancelAutoJoin(meetingID: meeting.id)

        XCTAssertFalse(store.isSkipped(meetingID: meeting.id))
    }

    func testSkipTodayDoesNotAffectAutoJoinCancelled() {
        let store = MeetingStore(fileURL: tempFileURL)
        let meeting = makeScheduledDailyMeeting()
        store.add(meeting)

        store.toggleSkip(meetingID: meeting.id)

        XCTAssertFalse(store.isAutoJoinCancelled(meetingID: meeting.id))
    }

    func testCancelAutoJoinPersistsAcrossInstances() {
        let store1 = MeetingStore(fileURL: tempFileURL)
        let meeting = makeScheduledDailyMeeting()
        store1.add(meeting)
        store1.cancelAutoJoin(meetingID: meeting.id)

        let store2 = MeetingStore(fileURL: tempFileURL)
        XCTAssertTrue(store2.isAutoJoinCancelled(meetingID: meeting.id))
    }

    func testDeletingMeetingRemovesAutoJoinCancelledException() {
        let store = MeetingStore(fileURL: tempFileURL)
        let meeting = makeScheduledDailyMeeting()
        store.add(meeting)
        store.cancelAutoJoin(meetingID: meeting.id)
        XCTAssertEqual(store.exceptions.count, 1)

        store.delete(id: meeting.id)

        XCTAssertTrue(store.exceptions.isEmpty)
    }
}
