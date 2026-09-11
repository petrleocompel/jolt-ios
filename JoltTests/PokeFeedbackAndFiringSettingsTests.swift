import XCTest
@testable import Jolt

final class FiringInteractionSettingsTests: XCTestCase {
    func testUniformAndSummary() {
        let uniform = FiringInteractionSettings.uniform(.hold)
        XCTAssertEqual(uniform.summaryLabel, "Hold")
        XCTAssertEqual(uniform[.zap], .hold)
        XCTAssertEqual(uniform[.vibe], .hold)
        XCTAssertEqual(uniform[.beep], .hold)

        var mixed = FiringInteractionSettings.default
        mixed[.zap] = .confirm
        XCTAssertEqual(mixed.summaryLabel, "Mixed")
    }

    func testJSONRoundTrip() throws {
        var settings = FiringInteractionSettings.default
        settings.zap = .confirm
        settings.vibe = .tap
        settings.beep = .hold
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(FiringInteractionSettings.self, from: data)
        XCTAssertEqual(settings, decoded)
    }
}

final class FiringInteractionSettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "FiringInteractionSettingsStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testMigratesLegacySingleMode() {
        defaults.set(FiringInteractionMode.hold.rawValue, forKey: "cz.peelco.jolt.firingInteractionMode")
        let store = FiringInteractionSettingsStore(defaults: defaults)
        let loaded = store.load()
        XCTAssertEqual(loaded, .uniform(.hold))
    }

    func testSaveClearsLegacyKey() {
        defaults.set(FiringInteractionMode.confirm.rawValue, forKey: "cz.peelco.jolt.firingInteractionMode")
        let store = FiringInteractionSettingsStore(defaults: defaults)
        store.save(.uniform(.tap))
        XCTAssertNil(defaults.string(forKey: "cz.peelco.jolt.firingInteractionMode"))
        XCTAssertEqual(store.load(), .uniform(.tap))
    }
}

final class PokeFeedbackSettingsTests: XCTestCase {
    func testPresets() {
        let off = PokeFeedbackSettings.preset(.off)
        XCTAssertFalse(off.isEnabled)

        let standard = PokeFeedbackSettings.preset(.standard)
        XCTAssertTrue(standard.showBanner)
        XCTAssertTrue(standard.flashButton)
        XCTAssertTrue(standard.playHaptic)
        XCTAssertFalse(standard.swapButtonLabel)

        let rich = PokeFeedbackSettings.preset(.rich)
        XCTAssertTrue(rich.swapButtonLabel)
    }

    func testReconcileProfileMarksCustom() {
        var settings = PokeFeedbackSettings.preset(.standard)
        settings.showBanner = false
        settings.reconcileProfile()
        XCTAssertEqual(settings.profile, .custom)

        settings = PokeFeedbackSettings.preset(.minimal)
        settings.reconcileProfile()
        XCTAssertEqual(settings.profile, .minimal)
    }
}

final class FriendPokeDraftTests: XCTestCase {
    func testPreferredDefaultWhenNothingSaved() {
        var permissions = FriendPermissionSet.none
        permissions.vibe = .allowed(maxIntensity: 80)
        permissions.zap = .allowed(maxIntensity: 40)

        let draft = FriendPokeDraft.resolved(saved: nil, permissions: permissions)
        XCTAssertEqual(draft?.kind, .vibe)
        XCTAssertEqual(draft?.intensity, 30)
    }

    func testRestoresSavedKindAndClampsIntensity() {
        var permissions = FriendPermissionSet.none
        permissions.vibe = .allowed(maxIntensity: 25)

        let draft = FriendPokeDraft.resolved(
            saved: FriendPokeDraft(kind: .vibe, intensity: 60),
            permissions: permissions
        )
        XCTAssertEqual(draft?.kind, .vibe)
        XCTAssertEqual(draft?.intensity, 25)
    }

    func testFallsBackWhenSavedKindNoLongerAllowed() {
        var permissions = FriendPermissionSet.none
        permissions.zap = .allowed(maxIntensity: 40)

        let draft = FriendPokeDraft.resolved(
            saved: FriendPokeDraft(kind: .vibe, intensity: 30),
            permissions: permissions
        )
        XCTAssertEqual(draft?.kind, .zap)
        XCTAssertEqual(draft?.intensity, 30)
    }

    func testNilWhenNothingAllowed() {
        let draft = FriendPokeDraft.resolved(saved: nil, permissions: .none)
        XCTAssertNil(draft)
    }
}

final class FriendPokeDraftStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "FriendPokeDraftStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testPerFriendIsolation() {
        let store = FriendPokeDraftStore(defaults: defaults)
        let alice = UUID()
        let bob = UUID()
        store.save(FriendPokeDraft(kind: .vibe, intensity: 40), for: alice)
        store.save(FriendPokeDraft(kind: .zap, intensity: 15), for: bob)

        XCTAssertEqual(store.load(friendID: alice)?.kind, .vibe)
        XCTAssertEqual(store.load(friendID: bob)?.intensity, 15)
    }
}
