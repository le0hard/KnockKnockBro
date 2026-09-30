import XCTest
@testable import KnockKnockBro

/// Проверка обновлений (v0.6.0): сравнение версий, разбор ответа GitHub,
/// автоматическая проверка не чаще раза в сутки. Без сети — загрузка
/// подменяется.
@MainActor
final class UpdateCheckerTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suiteName = "KnockKnockBroTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func releaseJSON(tag: String) -> Data {
        Data("""
        { "tag_name": "\(tag)", "html_url": "https://github.com/le0hard/KnockKnockBro/releases/tag/\(tag)", "name": "KnockKnockBro \(tag)" }
        """.utf8)
    }

    private func okResponse() -> URLResponse {
        HTTPURLResponse(url: UpdateChecker.latestReleaseURL, statusCode: 200, httpVersion: nil, headerFields: nil)!
    }

    // MARK: - Версии

    func testVersionComparison() {
        XCTAssertLessThan(AppVersion("0.9.0")!, AppVersion("0.10.0")!)
        XCTAssertLessThan(AppVersion("v0.5.0")!, AppVersion("0.6.0")!)
        XCTAssertEqual(AppVersion("1.0")!, AppVersion("v1.0.0")!)
        XCTAssertNil(AppVersion("beta"))
        XCTAssertNil(AppVersion("1.x"))
    }

    // MARK: - Разбор ответа

    func testParsesLatestRelease() throws {
        let release = try UpdateChecker.parseLatestRelease(from: releaseJSON(tag: "v0.6.0"))
        XCTAssertEqual(release.version, AppVersion("0.6.0"))
        XCTAssertEqual(release.pageURL.absoluteString, "https://github.com/le0hard/KnockKnockBro/releases/tag/v0.6.0")
    }

    func testEvaluateNewerOlderSame() throws {
        let release = try UpdateChecker.parseLatestRelease(from: releaseJSON(tag: "v0.6.0"))
        XCTAssertEqual(UpdateChecker.evaluate(release: release, currentVersion: "0.5.0"), .updateAvailable(release))
        XCTAssertEqual(UpdateChecker.evaluate(release: release, currentVersion: "0.6.0"), .upToDate(current: "0.6.0"))
        XCTAssertEqual(UpdateChecker.evaluate(release: release, currentVersion: "0.7.0"), .upToDate(current: "0.7.0"))
    }

    // MARK: - Когда проверяем

    func testAutomaticCheckRunsAtMostOncePerDay() async {
        var requests = 0
        let checker = UpdateChecker(defaults: defaults, currentVersion: "0.5.0") { [self] _ in
            requests += 1
            return (releaseJSON(tag: "v0.6.0"), okResponse())
        }
        let now = Date()

        await checker.checkIfNeeded(now: now)
        await checker.checkIfNeeded(now: now.addingTimeInterval(60 * 60))
        XCTAssertEqual(requests, 1, "Второй раз в течение суток сеть не трогаем")

        await checker.checkIfNeeded(now: now.addingTimeInterval(25 * 60 * 60))
        XCTAssertEqual(requests, 2)
        if case .updateAvailable = checker.lastResult {} else { XCTFail("Ожидалось «доступна новая версия»") }
    }

    func testAutomaticCheckIsSilentOnError() async {
        let checker = UpdateChecker(defaults: defaults, currentVersion: "0.5.0") { _ in
            throw URLError(.notConnectedToInternet)
        }
        await checker.checkIfNeeded()
        XCTAssertNil(checker.lastResult, "Автоматическая проверка не показывает ошибок")
        XCTAssertNil(checker.lastCheckDate, "Неудачная проверка не считается — повторим при следующем открытии")
    }

    func testManualCheckAlwaysRunsAndReportsErrors() async {
        var requests = 0
        let checker = UpdateChecker(defaults: defaults, currentVersion: "0.5.0") { _ in
            requests += 1
            let response = HTTPURLResponse(url: UpdateChecker.latestReleaseURL, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (Data(), response)
        }
        await checker.check()
        await checker.check()
        XCTAssertEqual(requests, 2)
        XCTAssertEqual(checker.lastResult, .failed(UpdateChecker.message(forStatusCode: 404)))
    }
}
