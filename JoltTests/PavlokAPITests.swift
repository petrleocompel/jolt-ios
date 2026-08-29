import XCTest
@testable import Jolt

/// Covers the parsing rules that were learned from real Pavlok responses (see
/// `docs/PAVLOK-API.md`), so a wrong assumption shows up here rather than as a
/// silently empty friends list.
final class PavlokAPITests: XCTestCase {
    // MARK: Permissions

    private func permission(zap: Bool = false, vibe: Bool = false, chime: Bool = false, maxZap: Int = 0) -> PavlokPokePermission {
        PavlokPokePermission(friendID: 1, canVibrate: vibe, canChime: chime, canZap: zap, maxZapValue: maxZap)
    }

    func testPermissionMapsPavlokVocabularyOntoStimulusKinds() {
        // "chime" is Pavlok's name for beep — the mapping is easy to get wrong.
        let grant = permission(zap: true, vibe: false, chime: true, maxZap: 40)
        XCTAssertTrue(grant.allows(.zap))
        XCTAssertTrue(grant.allows(.beep))
        XCTAssertFalse(grant.allows(.vibe))
    }

    func testOnlyZapIsIntensityCapped() {
        let grant = permission(zap: true, vibe: true, chime: true, maxZap: 40)
        XCTAssertEqual(grant.maxIntensity(for: .zap), 40)
        XCTAssertEqual(grant.maxIntensity(for: .vibe), 100)
        XCTAssertEqual(grant.maxIntensity(for: .beep), 100)
    }

    func testZapCapIsClampedIntoRange() {
        XCTAssertEqual(permission(zap: true, maxZap: 500).maxIntensity(for: .zap), 100)
        XCTAssertEqual(permission(zap: true, maxZap: -5).maxIntensity(for: .zap), 0)
    }

    func testNoneAllowsNothing() {
        for kind in StimulusKind.allCases {
            XCTAssertFalse(PavlokPokePermission.none.allows(kind))
        }
    }

    // MARK: Stimulus naming

    func testStimulusNamesMatchPavlokVocabulary() {
        // These exact strings are also the `types=` filter values.
        XCTAssertEqual(PavlokAPIClient.stimulusName(.zap), "Zap")
        XCTAssertEqual(PavlokAPIClient.stimulusName(.beep), "Beep")
        XCTAssertEqual(PavlokAPIClient.stimulusName(.vibe), "Vibe")
    }

    func testJournalNamesParseBackIntoKinds() {
        XCTAssertEqual(PavlokAPIClient.stimulusKind(named: "Zap"), .zap)
        XCTAssertEqual(PavlokAPIClient.stimulusKind(named: "vibe"), .vibe)
        XCTAssertEqual(PavlokAPIClient.stimulusKind(named: "Chime"), .beep)
        XCTAssertNil(PavlokAPIClient.stimulusKind(named: "Something else"))
    }

    // MARK: Dates

    func testBothTimestampFormsParse() {
        // Real journal rows carry both forms.
        XCTAssertNotNil(PavlokAPIClient.date(from: "2026-08-29T17:15:17Z"))
        XCTAssertNotNil(PavlokAPIClient.date(from: "2026-08-29T09:54:13.500000Z"))
        XCTAssertNil(PavlokAPIClient.date(from: "not a date"))
    }

    // MARK: Errors

    func testPlainStringErrorsAreSurfaced() {
        let json: [String: Any] = ["errors": ["Timestamp must be without timezone"]]
        XCTAssertEqual(
            PavlokAPIClient.errorMessage(from: json, status: 422),
            "Timestamp must be without timezone"
        )
    }

    func testValidationErrorsNameTheOffendingField() {
        let json: [String: Any] = [
            "errors": [["loc": ["body", "user"], "msg": "field required", "type": "value_error.missing"]]
        ]
        XCTAssertEqual(
            PavlokAPIClient.errorMessage(from: json, status: 422),
            "user: field required"
        )
    }

    func testUnparseableBodyFallsBackToStatus() {
        XCTAssertEqual(PavlokAPIClient.errorMessage(from: nil, status: 500), "Pavlok returned HTTP 500.")
    }

    // MARK: Display names

    func testFriendDisplayNameFallsBackThroughNameThenUsername() {
        XCTAssertEqual(
            PavlokFriend(id: 1, firstName: "A", lastName: "V", username: nil, profilePictureURL: nil).displayName,
            "A V"
        )
        XCTAssertEqual(
            PavlokFriend(id: 2, firstName: nil, lastName: nil, username: "leo", profilePictureURL: nil).displayName,
            "leo"
        )
        // Real rows often have null firstName/lastName *and* null username.
        XCTAssertEqual(
            PavlokFriend(id: 3, firstName: nil, lastName: nil, username: nil, profilePictureURL: nil).displayName,
            "Pavlok user 3"
        )
    }
}
