import XCTest
@testable import KnockKnockBro

final class MeetingCodableTests: XCTestCase {

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private let decoder = JSONDecoder()

    func testQuickRoomRoundTrip() throws {
        let meeting = Meeting(
            name: "Командная комната",
            url: URL(string: "https://telemost.yandex.ru/j/111")!,
            service: .yandexTelemost,
            type: .quickRoom
        )

        let data = try encoder.encode(meeting)
        let decoded = try decoder.decode(Meeting.self, from: data)

        XCTAssertEqual(decoded, meeting)
        XCTAssertNil(decoded.schedule)
        XCTAssertNil(decoded.autoJoin)
    }

    func testScheduledMeetingWithWeeklyRecurrenceRoundTrip() throws {
        let meeting = Meeting(
            name: "Project X Sync",
            url: URL(string: "https://meet.google.com/abc-defg-hij")!,
            service: .googleMeet,
            type: .scheduled,
            schedule: MeetingSchedule(hour: 14, minute: 30, recurrence: .weekly(.monday)),
            reminders: [
                MeetingReminder(offsetBeforeStart: 15 * 60, sound: .system),
                MeetingReminder(offsetBeforeStart: 5 * 60, sound: .short),
                MeetingReminder(offsetBeforeStart: 0, sound: .system),
            ],
            autoJoin: AutoJoinSettings(isEnabled: true, countdownOverride: 10)
        )

        let data = try encoder.encode(meeting)
        let decoded = try decoder.decode(Meeting.self, from: data)

        XCTAssertEqual(decoded, meeting)
        XCTAssertEqual(decoded.reminders.count, 3)
        XCTAssertEqual(decoded.schedule?.recurrence, .weekly(.monday))
    }

    func testScheduledMeetingWithCustomDaysRecurrenceRoundTrip() throws {
        let meeting = Meeting(
            name: "Design Review",
            url: URL(string: "https://teams.microsoft.com/l/meetup-join/abc")!,
            service: .microsoftTeams,
            type: .scheduled,
            enabled: false,
            schedule: MeetingSchedule(hour: 17, minute: 0, recurrence: .customDays([.monday, .wednesday, .friday]))
        )

        let data = try encoder.encode(meeting)
        let decoded = try decoder.decode(Meeting.self, from: data)

        XCTAssertEqual(decoded, meeting)
        XCTAssertFalse(decoded.enabled)
        XCTAssertEqual(decoded.schedule?.recurrence, .customDays([.monday, .wednesday, .friday]))
    }

    func testUnknownServicePreservesHostnameThroughRoundTrip() throws {
        let meeting = Meeting(
            name: "Тестовая комната",
            url: URL(string: "https://my-custom-meet.example.com/room/1")!,
            service: .unknown(hostname: "my-custom-meet.example.com"),
            type: .quickRoom
        )

        let data = try encoder.encode(meeting)
        let decoded = try decoder.decode(Meeting.self, from: data)

        XCTAssertEqual(decoded, meeting)
        if case .unknown(let hostname) = decoded.service {
            XCTAssertEqual(hostname, "my-custom-meet.example.com")
        } else {
            XCTFail("Ожидался .unknown сервис")
        }
    }

    func testRecurrenceJSONUsesReadableDiscriminator() throws {
        let recurrence = Recurrence.weekly(.monday)
        let data = try encoder.encode(recurrence)
        let json = String(data: data, encoding: .utf8)!

        XCTAssertTrue(json.contains("\"type\""))
        XCTAssertTrue(json.contains("\"weekly\""))
        XCTAssertTrue(json.contains("\"weekday\""))
    }

    func testMeetingJSONUsesNotificationsKeyForReminders() throws {
        let meeting = Meeting(
            name: "Daily",
            url: URL(string: "https://telemost.yandex.ru/j/123456789")!,
            service: .yandexTelemost,
            type: .scheduled,
            schedule: MeetingSchedule(hour: 10, minute: 0, recurrence: .daily),
            reminders: [MeetingReminder(offsetBeforeStart: 15 * 60)]
        )

        let data = try encoder.encode(meeting)
        let json = String(data: data, encoding: .utf8)!

        XCTAssertTrue(json.contains("\"notifications\""))
        XCTAssertFalse(json.contains("\"reminders\""))
    }
}
