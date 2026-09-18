import XCTest
import AppKit
@testable import KnockKnockBro

final class MeetingLauncherTests: XCTestCase {

    func testCopyURLPutsAbsoluteStringOnPasteboard() {
        let url = URL(string: "https://telemost.yandex.ru/j/123456789")!
        MeetingLauncher.copyURL(url)
        let copiedString = NSPasteboard.general.string(forType: .string)
        XCTAssertEqual(copiedString, "https://telemost.yandex.ru/j/123456789")
    }

    func testCopyURLOverwritesPreviousPasteboardContent() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("что-то старое", forType: .string)

        let url = URL(string: "https://meet.google.com/abc-defg-hij")!
        MeetingLauncher.copyURL(url)

        XCTAssertEqual(pasteboard.string(forType: .string), "https://meet.google.com/abc-defg-hij")
    }

    // MARK: - Telemost deep link

    func testTelemostDeepLinkTransformsURLCorrectly() {
        let url = URL(string: "https://telemost.yandex.ru/j/40555823510244")!
        let deepLink = MeetingLauncher.telemostDeepLink(from: url)

        XCTAssertEqual(deepLink?.absoluteString, "telemost://https//telemost.yandex.ru/j/40555823510244")
    }

    func testTelemostDeepLinkReturnsNilForNonHTTPSURL() {
        let url = URL(string: "ftp://telemost.yandex.ru/j/123")!
        XCTAssertNil(MeetingLauncher.telemostDeepLink(from: url))
    }

    // MARK: - connectOptions: non-Telemost services

    func testConnectOptionsForNonTelemostServiceAlwaysSingleButton() {
        let meeting = Meeting(
            name: "Standup",
            url: URL(string: "https://meet.google.com/abc-defg-hij")!,
            service: .googleMeet,
            type: .quickRoom
        )

        let options = MeetingLauncher.connectOptions(for: meeting, telemostMode: .both, appAvailabilityCheck: { true })

        XCTAssertEqual(options.count, 1)
        XCTAssertEqual(options.first?.title, "Подключиться")
        XCTAssertEqual(options.first?.url, meeting.url)
    }

    // MARK: - connectOptions: Telemost, webOnly

    func testConnectOptionsWebOnlyIgnoresAppAvailability() {
        let meeting = makeTelemostMeeting()

        let options = MeetingLauncher.connectOptions(for: meeting, telemostMode: .webOnly, appAvailabilityCheck: { true })

        XCTAssertEqual(options.count, 1)
        XCTAssertEqual(options.first?.title, "Подключиться")
        XCTAssertEqual(options.first?.url, meeting.url)
    }

    // MARK: - connectOptions: Telemost, desktopOnly

    func testConnectOptionsDesktopOnlyWithAppAvailableUsesDeepLink() {
        let meeting = makeTelemostMeeting()

        let options = MeetingLauncher.connectOptions(for: meeting, telemostMode: .desktopOnly, appAvailabilityCheck: { true })

        XCTAssertEqual(options.count, 1)
        XCTAssertEqual(options.first?.title, "Подключиться")
        XCTAssertEqual(options.first?.url, MeetingLauncher.telemostDeepLink(from: meeting.url))
    }

    func testConnectOptionsDesktopOnlyWithAppUnavailableFallsBackToWeb() {
        let meeting = makeTelemostMeeting()

        let options = MeetingLauncher.connectOptions(for: meeting, telemostMode: .desktopOnly, appAvailabilityCheck: { false })

        XCTAssertEqual(options.count, 1)
        XCTAssertEqual(options.first?.title, "Подключиться")
        XCTAssertEqual(options.first?.url, meeting.url)
    }

    // MARK: - connectOptions: Telemost, both

    func testConnectOptionsBothWithAppAvailableReturnsTwoButtons() {
        let meeting = makeTelemostMeeting()

        let options = MeetingLauncher.connectOptions(for: meeting, telemostMode: .both, appAvailabilityCheck: { true })

        XCTAssertEqual(options.count, 2)
        XCTAssertEqual(options[0].title, "Подключиться")
        XCTAssertEqual(options[0].url, MeetingLauncher.telemostDeepLink(from: meeting.url))
        XCTAssertEqual(options[1].title, "Подключиться web")
        XCTAssertEqual(options[1].url, meeting.url)
    }

    func testConnectOptionsBothWithAppUnavailableCollapsesToSingleWebButton() {
        let meeting = makeTelemostMeeting()

        let options = MeetingLauncher.connectOptions(for: meeting, telemostMode: .both, appAvailabilityCheck: { false })

        XCTAssertEqual(options.count, 1)
        XCTAssertEqual(options.first?.title, "Подключиться")
        XCTAssertEqual(options.first?.url, meeting.url)
    }

    // MARK: - Helpers

    private func makeTelemostMeeting() -> Meeting {
        Meeting(
            name: "Daily",
            url: URL(string: "https://telemost.yandex.ru/j/40555823510244")!,
            service: .yandexTelemost,
            type: .quickRoom
        )
    }
}
