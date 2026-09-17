import XCTest
@testable import KnockKnockBro

final class MeetingProviderDetectorTests: XCTestCase {

    func testYandexTelemost() {
        let url = URL(string: "https://telemost.yandex.ru/j/123456789")!
        XCTAssertEqual(MeetingProviderDetector.detectService(from: url), .yandexTelemost)
    }

    func testGoogleMeet() {
        let url = URL(string: "https://meet.google.com/abc-defg-hij")!
        XCTAssertEqual(MeetingProviderDetector.detectService(from: url), .googleMeet)
    }

    func testZoomRootDomain() {
        let url = URL(string: "https://zoom.us/j/123456789")!
        XCTAssertEqual(MeetingProviderDetector.detectService(from: url), .zoom)
    }

    func testZoomSubdomain() {
        let url = URL(string: "https://company.zoom.us/j/123456789")!
        XCTAssertEqual(MeetingProviderDetector.detectService(from: url), .zoom)
    }

    func testMicrosoftTeamsVariantOne() {
        let url = URL(string: "https://teams.microsoft.com/l/meetup-join/abc")!
        XCTAssertEqual(MeetingProviderDetector.detectService(from: url), .microsoftTeams)
    }

    func testMicrosoftTeamsVariantTwo() {
        let url = URL(string: "https://teams.live.com/meet/abc")!
        XCTAssertEqual(MeetingProviderDetector.detectService(from: url), .microsoftTeams)
    }

    func testUnknownHostFallsBackGracefully() {
        let url = URL(string: "https://my-custom-meet.example.com/room/1")!
        XCTAssertEqual(
            MeetingProviderDetector.detectService(from: url),
            .unknown(hostname: "my-custom-meet.example.com")
        )
    }

    func testHostnameMatchingIsCaseInsensitive() {
        let url = URL(string: "https://TELEMOST.YANDEX.RU/j/123")!
        XCTAssertEqual(MeetingProviderDetector.detectService(from: url), .yandexTelemost)
    }

    func testDoesNotFalsePositiveOnUnrelatedDomainContainingSubstring() {
        // "notzoom.us" НЕ должен определяться как zoom.us — суффиксная
        // проверка обязана требовать точку-разделитель перед суффиксом.
        let url = URL(string: "https://notzoom.us/room")!
        XCTAssertEqual(MeetingProviderDetector.detectService(from: url), .unknown(hostname: "notzoom.us"))
    }
}
