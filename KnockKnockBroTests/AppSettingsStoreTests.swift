import XCTest
@testable import KnockKnockBro

final class AppSettingsStoreTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "KnockKnockBroTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
    }

    func testDefaultsToFallbackValueWhenNothingStored() {
        let store = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(store.defaultAutoJoinCountdown, AppSettingsStore.fallbackDefaultCountdown)
    }

    func testPersistsChangedValueAcrossInstances() {
        let store1 = AppSettingsStore(defaults: defaults)
        store1.defaultAutoJoinCountdown = 30

        let store2 = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(store2.defaultAutoJoinCountdown, 30)
    }

    // MARK: - showInMenuBar

    func testShowInMenuBarDefaultsToTrueWhenNothingStored() {
        let store = AppSettingsStore(defaults: defaults)
        XCTAssertTrue(store.showInMenuBar)
    }

    func testShowInMenuBarPersistsAcrossInstances() {
        let store1 = AppSettingsStore(defaults: defaults)
        store1.showInMenuBar = false

        let store2 = AppSettingsStore(defaults: defaults)
        XCTAssertFalse(store2.showInMenuBar)
    }

    // MARK: - openMainWindowOnLaunch

    func testOpenMainWindowOnLaunchDefaultsToFalseWhenNothingStored() {
        let store = AppSettingsStore(defaults: defaults)
        XCTAssertFalse(store.openMainWindowOnLaunch)
    }

    func testOpenMainWindowOnLaunchPersistsAcrossInstances() {
        let store1 = AppSettingsStore(defaults: defaults)
        store1.openMainWindowOnLaunch = true

        let store2 = AppSettingsStore(defaults: defaults)
        XCTAssertTrue(store2.openMainWindowOnLaunch)
    }
}
