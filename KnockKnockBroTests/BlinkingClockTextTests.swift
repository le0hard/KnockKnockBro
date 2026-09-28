import XCTest
@testable import KnockKnockBro

final class BlinkingClockTextTests: XCTestCase {
    func testColonIsFullyVisibleAtCycleStart() {
        let date = Date(timeIntervalSinceReferenceDate: BlinkingClockText.blinkPeriod * 1000)
        XCTAssertEqual(BlinkingClockText.colonOpacity(at: date), 1, accuracy: 0.0001)
    }

    func testColonIsDimmestAtHalfCycle() {
        let date = Date(timeIntervalSinceReferenceDate: BlinkingClockText.blinkPeriod * 1000.5)
        XCTAssertEqual(BlinkingClockText.colonOpacity(at: date), BlinkingClockText.minimumColonOpacity, accuracy: 0.0001)
    }

    func testSameMomentGivesSameOpacityForAllClocks() {
        // Синхронность: фаза зависит только от абсолютного времени.
        let now = Date()
        XCTAssertEqual(BlinkingClockText.colonOpacity(at: now), BlinkingClockText.colonOpacity(at: now))
    }
}
