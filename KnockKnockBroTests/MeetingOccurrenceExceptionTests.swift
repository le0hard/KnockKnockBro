import XCTest
@testable import KnockKnockBro

final class MeetingOccurrenceExceptionTests: XCTestCase {

    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
        return calendar
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0, calendar: Calendar) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }

    func testRoundTripCodable() throws {
        let cal = calendar()
        let exception = MeetingOccurrenceException(
            meetingID: UUID(),
            date: date(year: 2026, month: 9, day: 16, calendar: cal),
            isSkipped: true,
            calendar: cal
        )

        let data = try JSONEncoder().encode(exception)
        let decoded = try JSONDecoder().decode(MeetingOccurrenceException.self, from: data)

        XCTAssertEqual(decoded, exception)
    }

    func testMatchesSameCalendarDayIgnoringTime() {
        let cal = calendar()
        let meetingID = UUID()
        let exception = MeetingOccurrenceException(
            meetingID: meetingID,
            date: date(year: 2026, month: 9, day: 16, hour: 10, calendar: cal),
            isSkipped: true,
            calendar: cal
        )

        let laterSameDay = date(year: 2026, month: 9, day: 16, hour: 23, minute: 59, calendar: cal)
        XCTAssertTrue(exception.matches(meetingID: meetingID, date: laterSameDay, calendar: cal))
    }

    func testDoesNotMatchDifferentDay() {
        let cal = calendar()
        let meetingID = UUID()
        let exception = MeetingOccurrenceException(
            meetingID: meetingID,
            date: date(year: 2026, month: 9, day: 16, calendar: cal),
            isSkipped: true,
            calendar: cal
        )

        let nextDay = date(year: 2026, month: 9, day: 17, calendar: cal)
        XCTAssertFalse(exception.matches(meetingID: meetingID, date: nextDay, calendar: cal))
    }

    func testDoesNotMatchDifferentMeeting() {
        let cal = calendar()
        let exception = MeetingOccurrenceException(
            meetingID: UUID(),
            date: date(year: 2026, month: 9, day: 16, calendar: cal),
            isSkipped: true,
            calendar: cal
        )

        let sameDay = date(year: 2026, month: 9, day: 16, calendar: cal)
        XCTAssertFalse(exception.matches(meetingID: UUID(), date: sameDay, calendar: cal))
    }

    // MARK: - autoJoinCancelled

    func testAutoJoinCancelledRoundTripsThroughCodable() throws {
        let cal = calendar()
        let exception = MeetingOccurrenceException(
            meetingID: UUID(),
            date: date(year: 2026, month: 9, day: 16, calendar: cal),
            isSkipped: false,
            autoJoinCancelled: true,
            calendar: cal
        )

        let data = try JSONEncoder().encode(exception)
        let decoded = try JSONDecoder().decode(MeetingOccurrenceException.self, from: data)

        XCTAssertEqual(decoded, exception)
        XCTAssertTrue(decoded.autoJoinCancelled)
        XCTAssertFalse(decoded.isSkipped)
    }

    func testLegacyJSONWithoutAutoJoinCancelledKeyDecodesAsFalse() throws {
        let legacyJSON = """
        {
          "id": "\(UUID().uuidString)",
          "meetingID": "\(UUID().uuidString)",
          "year": 2026,
          "month": 9,
          "day": 16,
          "isSkipped": true
        }
        """
        let decoded = try JSONDecoder().decode(MeetingOccurrenceException.self, from: Data(legacyJSON.utf8))

        XCTAssertTrue(decoded.isSkipped)
        XCTAssertFalse(decoded.autoJoinCancelled)
    }
}
