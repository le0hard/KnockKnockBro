import XCTest
import AppKit
@testable import KnockKnockBro

final class MeetingLauncherTests: XCTestCase {

    /// `MeetingLauncher.open` вызывает `NSWorkspace.shared.open`, который
    /// реально открывает внешние приложения — юнит-тестами это напрямую
    /// не проверяется (это было бы интеграционным, а не unit-тестом, и
    /// засоряло бы систему тестового окружения открытыми окнами браузера).
    /// Здесь проверяется единственное, что можно и нужно проверить
    /// изолированно: копирование ссылки в буфер обмена.
    func testCopyURLPutsAbsoluteStringOnPasteboard() {
        let url = URL(string: "https://telemost.yandex.ru/j/123456789")!

        MeetingLauncher.copyURL(url)

        let pasteboard = NSPasteboard.general
        let copiedString = pasteboard.string(forType: .string)

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
}
