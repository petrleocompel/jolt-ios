import XCTest
@testable import Jolt

final class QuickPokeSettingsTests: XCTestCase {
    func testIsConfiguredNeedsEnabledAndFriend() {
        var settings = QuickPokeSettings.default
        XCTAssertFalse(settings.isConfigured)          // default: nothing set
        settings.isEnabled = true
        XCTAssertFalse(settings.isConfigured)           // enabled but no friend
        settings.targetFriendID = UUID()
        XCTAssertTrue(settings.isConfigured)
        settings.isEnabled = false
        XCTAssertFalse(settings.isConfigured)            // disabled overrides
    }

    func testSettingsSurviveJSONRoundTrip() throws {
        var settings = QuickPokeSettings.default
        settings.isEnabled = true
        settings.targetFriendID = UUID()
        settings.targetFriendName = "Alice"
        settings.stimulus = StimulusConfig(kind: .zap, intensity: 55, repetitions: 3)

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(QuickPokeSettings.self, from: data)
        XCTAssertEqual(settings, decoded)
    }
}

final class QuickPokeSettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "QuickPokeSettingsStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testLoadReturnsDefaultWhenNothingSaved() {
        let store = QuickPokeSettingsStore(defaults: defaults)
        XCTAssertEqual(store.load(), .default)
    }

    func testSaveThenLoadRoundTrips() {
        let store = QuickPokeSettingsStore(defaults: defaults)
        let friendID = UUID()
        var settings = QuickPokeSettings.default
        settings.isEnabled = true
        settings.targetFriendID = friendID
        settings.targetFriendName = "Bob"
        store.save(settings)

        let loaded = store.load()
        XCTAssertEqual(loaded.isEnabled, true)
        XCTAssertEqual(loaded.targetFriendID, friendID)
        XCTAssertEqual(loaded.targetFriendName, "Bob")
    }

    func testResetRemovesSavedSettings() {
        let store = QuickPokeSettingsStore(defaults: defaults)
        var settings = QuickPokeSettings.default
        settings.isEnabled = true
        settings.targetFriendID = UUID()
        store.save(settings)

        store.reset()
        XCTAssertEqual(store.load(), .default)
    }
}
