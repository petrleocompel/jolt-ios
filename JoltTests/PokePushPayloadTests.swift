import XCTest
@testable import Jolt

final class PokePushPayloadTests: XCTestCase {
    func testParsesValidPokeUserInfo() throws {
        let pokeID = UUID()
        let userInfo: [AnyHashable: Any] = [
            "type": "poke",
            "poke": [
                "pokeID": pokeID.uuidString,
                "senderHandle": "alice",
                "senderDisplayName": "Alice",
                "stimulus": ["kind": "zap", "intensity": 30, "repetitions": 1]
            ]
        ]

        let payload = try XCTUnwrap(PokePushPayload(userInfo: userInfo))
        XCTAssertEqual(payload.pokeID, pokeID)
        XCTAssertEqual(payload.senderHandle, "alice")
        XCTAssertEqual(payload.stimulus.kind, .zap)
        XCTAssertEqual(payload.stimulus.intensity, 30)
    }

    func testReadsTheAutomationFlag() throws {
        let userInfo: [AnyHashable: Any] = [
            "type": "poke",
            "poke": [
                "pokeID": UUID().uuidString,
                "senderHandle": "alice",
                "senderDisplayName": "Alice",
                "recipientHandle": "bob",
                "stimulus": ["kind": "vibe", "intensity": 30, "repetitions": 1],
                "sentAt": "2026-09-21T14:32:00Z",
                "viaApiToken": true
            ]
        ]

        let payload = try XCTUnwrap(PokePushPayload(userInfo: userInfo))
        XCTAssertEqual(payload.viaApiToken, true)
    }

    /// A server that predates the flag still gets its pokes fired.
    func testParsesAPayloadWithoutTheAutomationFlag() throws {
        let userInfo: [AnyHashable: Any] = [
            "type": "poke",
            "poke": [
                "pokeID": UUID().uuidString,
                "senderHandle": "alice",
                "senderDisplayName": "Alice",
                "stimulus": ["kind": "zap", "intensity": 30, "repetitions": 1]
            ]
        ]

        let payload = try XCTUnwrap(PokePushPayload(userInfo: userInfo))
        XCTAssertNil(payload.viaApiToken)
    }

    func testReturnsNilForNonPokeType() {
        let userInfo: [AnyHashable: Any] = ["type": "alarm", "alarmID": UUID().uuidString]
        XCTAssertNil(PokePushPayload(userInfo: userInfo))
    }

    func testReturnsNilForMalformedPokePayload() {
        let userInfo: [AnyHashable: Any] = ["type": "poke", "poke": ["senderHandle": "alice"]]
        XCTAssertNil(PokePushPayload(userInfo: userInfo))
    }
}
