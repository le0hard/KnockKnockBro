import XCTest
@testable import KnockKnockBro

/// Аудит импорта/экспорта v0.6.0: полный цикл для всех видов данных,
/// настройки приложения (формат 3), строгая проверка и объединение.
final class ImportExportFullCycleTests: XCTestCase {

    // MARK: - Helpers

    private let url = URL(string: "https://telemost.yandex.ru/j/1")!

    private func scheduled(
        name: String = "Daily",
        id: UUID = UUID(),
        recurrence: Recurrence = .weekdays,
        reminders: [MeetingReminder] = [],
        autoJoin: AutoJoinSettings? = nil
    ) -> Meeting {
        Meeting(
            id: id,
            name: name,
            url: url,
            service: .yandexTelemost,
            type: .scheduled,
            schedule: MeetingSchedule(hour: 10, minute: 30, recurrence: recurrence),
            reminders: reminders,
            autoJoin: autoJoin
        )
    }

    private let settings = AppSettingsSnapshot(
        defaultAutoJoinCountdown: 15,
        telemostConnectionMode: .desktopOnly,
        joinCountingWindowMinutes: 20,
        showInMenuBar: true,
        openMainWindowOnLaunch: true,
        launchAtLogin: true
    )

    private func validated(_ data: Data, file: StaticString = #filePath, line: UInt = #line) -> ValidatedImport? {
        switch ImportExportService.validate(data: data) {
        case .success(let value):
            return value
        case .failure(let error):
            XCTFail("Ожидалась успешная валидация: \(error.localizedDescription)", file: file, line: line)
            return nil
        }
    }

    private func failure(_ json: String) -> ImportValidationError? {
        if case .failure(let error) = ImportExportService.validate(data: Data(json.utf8)) { return error }
        return nil
    }

    private func meetingJSON(name: String = "Daily", notifications: String = "[]", extra: String = "") -> String {
        """
        {
          "id": "\(UUID().uuidString)",
          "name": "\(name)",
          "url": "https://telemost.yandex.ru/j/1",
          "service": { "type": "yandexTelemost" },
          "type": "scheduled",
          "enabled": true,
          "schedule": { "hour": 10, "minute": 0, "recurrence": { "type": "daily" } },
          "notifications": \(notifications)\(extra)
        }
        """
    }

    // MARK: - Полный цикл

    func testFullRoundTripKeepsEverything() throws {
        let room = Meeting(
            name: "Командная комната",
            url: URL(string: "https://meet.google.com/abc-defg-hij")!,
            service: .googleMeet,
            type: .quickRoom,
            enabled: false
        )
        let unknownService = Meeting(
            name: "Своя платформа",
            url: URL(string: "https://calls.example.com/room/42")!,
            service: .unknown(hostname: "calls.example.com"),
            type: .quickRoom
        )
        let daily = scheduled(
            name: "Daily",
            recurrence: .daily,
            reminders: [
                MeetingReminder(offsetBeforeStart: 15 * 60, sound: .short),
                MeetingReminder(offsetBeforeStart: 0, sound: .none),
            ],
            autoJoin: AutoJoinSettings(isEnabled: true, countdownOverride: 30)
        )
        let weekly = scheduled(name: "Планёрка", recurrence: .weekly(.monday), autoJoin: AutoJoinSettings(isEnabled: false))
        let custom = scheduled(name: "Спорт", recurrence: .customDays([.tuesday, .thursday]))
        let once = scheduled(name: "Демо", recurrence: .once(CalendarDay(year: 2026, month: 11, day: 3), autoDelete: true))
        let onceKept = scheduled(name: "Интервью", recurrence: .once(CalendarDay(year: 2026, month: 11, day: 4), autoDelete: false))
        let meetings = [room, unknownService, daily, weekly, custom, once, onceKept]

        let day = Date(timeIntervalSince1970: 1_790_000_000)
        let exceptions = [
            MeetingOccurrenceException(meetingID: daily.id, date: day, isSkipped: true),
            MeetingOccurrenceException(meetingID: weekly.id, date: day, autoJoinCancelled: true, joined: true),
        ]

        let data = try ImportExportService.export(meetings: meetings, exceptions: exceptions, settings: settings)
        guard let imported = validated(data) else { return }

        XCTAssertEqual(imported.meetings, meetings)
        XCTAssertEqual(imported.exceptions, exceptions)
        XCTAssertEqual(imported.settings, settings)
    }

    func testExportWithoutSettingsHasNoSettingsKey() throws {
        let data = try ImportExportService.export(meetings: [scheduled()], exceptions: [])
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNil(json?["settings"])
        XCTAssertEqual(json?["formatVersion"] as? Int, MeetingStore.currentFormatVersion)
    }

    func testSettingsAreHumanReadable() throws {
        let data = try ImportExportService.export(meetings: [], exceptions: [], settings: settings)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let block = json?["settings"] as? [String: Any]
        XCTAssertEqual(block?["telemostConnectionMode"] as? String, "desktopOnly")
        XCTAssertEqual(block?["joinCountingWindowMinutes"] as? Int, 20)
        XCTAssertEqual(block?["launchAtLogin"] as? Bool, true)
    }

    // MARK: - Старые форматы

    func testFormat2FileImportsWithoutSettings() {
        let json = """
        { "formatVersion": 2, "meetings": [\(meetingJSON())] }
        """
        guard let imported = validated(Data(json.utf8)) else { return }
        XCTAssertEqual(imported.meetings.count, 1)
        XCTAssertNil(imported.settings)
    }

    func testFutureFormatIsRejected() {
        XCTAssertEqual(
            failure(#"{ "formatVersion": 4, "meetings": [] }"#),
            .unsupportedFormatVersion(found: 4, supported: MeetingStore.currentFormatVersion)
        )
    }

    // MARK: - Строгая проверка

    func testRejectsEmptyName() {
        XCTAssertEqual(failure(#"{ "formatVersion": 3, "meetings": [\#(meetingJSON(name: "   "))] }"#), .emptyMeetingName)
    }

    func testRejectsNegativeReminder() {
        let notifications = #"[{ "id": "\#(UUID().uuidString)", "offsetBeforeStart": -60, "sound": "system" }]"#
        XCTAssertEqual(
            failure(#"{ "formatVersion": 3, "meetings": [\#(meetingJSON(notifications: notifications))] }"#),
            .invalidReminder(meetingName: "Daily")
        )
    }

    func testRejectsDuplicateReminderIDs() {
        let id = UUID().uuidString
        let notifications = #"[{ "id": "\#(id)", "offsetBeforeStart": 60, "sound": "system" }, { "id": "\#(id)", "offsetBeforeStart": 0, "sound": "none" }]"#
        XCTAssertEqual(
            failure(#"{ "formatVersion": 3, "meetings": [\#(meetingJSON(notifications: notifications))] }"#),
            .invalidReminder(meetingName: "Daily")
        )
    }

    func testRejectsZeroAutoJoinCountdown() {
        let extra = #", "autoJoin": { "isEnabled": true, "countdownOverride": 0 }"#
        XCTAssertEqual(
            failure(#"{ "formatVersion": 3, "meetings": [\#(meetingJSON(extra: extra))] }"#),
            .invalidAutoJoinCountdown(meetingName: "Daily")
        )
    }

    func testRejectsExceptionWithNonexistentDate() throws {
        let meeting = scheduled()
        var exception = MeetingOccurrenceException(meetingID: meeting.id, date: Date())
        exception.month = 2
        exception.day = 30
        let data = try ImportExportService.export(meetings: [meeting], exceptions: [exception])
        if case .failure(let error) = ImportExportService.validate(data: data) {
            XCTAssertEqual(error, .invalidException)
        } else {
            XCTFail("30 февраля в отметке не должно импортироваться")
        }
    }

    func testRejectsTwoExceptionsForSameDay() throws {
        let meeting = scheduled()
        let day = Date()
        let data = try ImportExportService.export(meetings: [meeting], exceptions: [
            MeetingOccurrenceException(meetingID: meeting.id, date: day, isSkipped: true),
            MeetingOccurrenceException(meetingID: meeting.id, date: day, joined: true),
        ])
        if case .failure(let error) = ImportExportService.validate(data: data) {
            XCTAssertEqual(error, .duplicateException)
        } else {
            XCTFail("Две отметки на один день не должны импортироваться")
        }
    }

    func testRejectsOutOfRangeSettings() throws {
        var bad = settings
        bad.joinCountingWindowMinutes = 500
        let data = try ImportExportService.export(meetings: [], exceptions: [], settings: bad)
        if case .failure(let error) = ImportExportService.validate(data: data) {
            XCTAssertEqual(error, .invalidSettings)
        } else {
            XCTFail("Окно засчитывания 500 минут не должно импортироваться")
        }
    }

    func testRejectsUnknownTelemostMode() {
        let json = """
        { "formatVersion": 3, "meetings": [], "settings": {
          "defaultAutoJoinCountdown": 10, "telemostConnectionMode": "teleport",
          "joinCountingWindowMinutes": 15, "showInMenuBar": true,
          "openMainWindowOnLaunch": false, "launchAtLogin": false } }
        """
        XCTAssertEqual(failure(json), .malformedJSON)
    }

    // MARK: - Объединение

    func testMergeAddsUpdatesAndKeeps() {
        let kept = scheduled(name: "Моя встреча")
        let toUpdate = scheduled(name: "Daily")
        let current = [kept, toUpdate]

        var updated = toUpdate
        updated.name = "Daily (новое время)"
        let added = scheduled(name: "Новая")
        let imported = ValidatedImport(meetings: [updated, added], exceptions: [], settings: nil)

        let result = ImportExportService.merged(currentMeetings: current, currentExceptions: [], imported: imported)

        XCTAssertEqual(result.meetings.map(\.name), ["Моя встреча", "Daily (новое время)", "Новая"])
        XCTAssertEqual(
            ImportExportService.mergeSummary(currentMeetings: current, imported: imported),
            MergeSummary(added: 1, updated: 1, unchanged: 0, skippedDuplicates: 0)
        )
    }

    func testMergeSkipsDuplicateWithDifferentID() {
        let existing = scheduled(name: "Daily")
        let duplicate = scheduled(name: "  daily ")
        let imported = ValidatedImport(
            meetings: [duplicate],
            exceptions: [MeetingOccurrenceException(meetingID: duplicate.id, date: Date(), isSkipped: true)],
            settings: nil
        )

        let result = ImportExportService.merged(currentMeetings: [existing], currentExceptions: [], imported: imported)

        XCTAssertEqual(result.meetings, [existing])
        XCTAssertTrue(result.exceptions.isEmpty, "Отметки пропущенного дубликата не переносятся")
        XCTAssertEqual(
            ImportExportService.mergeSummary(currentMeetings: [existing], imported: imported).skippedDuplicates, 1
        )
    }

    func testMergeReplacesExceptionsOnlyForImportedMeetings() {
        let keptMeeting = scheduled(name: "Моя")
        let shared = scheduled(name: "Общая")
        let day = Date()
        let keptException = MeetingOccurrenceException(meetingID: keptMeeting.id, date: day, isSkipped: true)
        let oldSharedException = MeetingOccurrenceException(meetingID: shared.id, date: day, isSkipped: true)
        let newSharedException = MeetingOccurrenceException(meetingID: shared.id, date: day, joined: true)

        let result = ImportExportService.merged(
            currentMeetings: [keptMeeting, shared],
            currentExceptions: [keptException, oldSharedException],
            imported: ValidatedImport(meetings: [shared], exceptions: [newSharedException], settings: nil)
        )

        XCTAssertEqual(Set(result.exceptions.map(\.id)), [keptException.id, newSharedException.id])
    }

    func testMergeSummaryCountsUnchanged() {
        let meeting = scheduled()
        let imported = ValidatedImport(meetings: [meeting], exceptions: [], settings: nil)
        XCTAssertEqual(
            ImportExportService.mergeSummary(currentMeetings: [meeting], imported: imported),
            MergeSummary(added: 0, updated: 0, unchanged: 1, skippedDuplicates: 0)
        )
    }

    // MARK: - Настройки приложения

    func testSettingsSnapshotAndApply() {
        let suite = "KnockKnockBroTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = AppSettingsStore(defaults: defaults)
        store.apply(settings)

        XCTAssertEqual(store.snapshot(launchAtLogin: true), settings)
        XCTAssertEqual(AppSettingsStore(defaults: defaults).snapshot(launchAtLogin: true), settings, "Сохраняется в UserDefaults")
    }
}
