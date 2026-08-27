import XCTest
@testable import Jolt

final class FriendPermissionSetTests: XCTestCase {
    func testNoneDisablesAllKinds() {
        let set = FriendPermissionSet.none
        XCTAssertTrue(set.allowedKinds.isEmpty)
        XCTAssertFalse(set.zap.isAllowed)
        XCTAssertFalse(set.vibe.isAllowed)
        XCTAssertFalse(set.beep.isAllowed)
    }

    func testSubscriptGetsAndSetsPerKind() {
        var set = FriendPermissionSet.none
        set[.zap] = .allowed(maxIntensity: 40, cooldownSeconds: 90)

        XCTAssertTrue(set[.zap].isAllowed)
        XCTAssertEqual(set[.zap].maxIntensity, 40)
        XCTAssertEqual(set[.zap].cooldownSeconds, 90)
        XCTAssertFalse(set[.vibe].isAllowed)
    }

    func testAllowedKindsReflectsOnlyAllowedEntries() {
        var set = FriendPermissionSet.none
        set[.vibe] = .allowed()
        set[.beep] = .allowed()

        XCTAssertEqual(Set(set.allowedKinds), [.vibe, .beep])
    }
}
