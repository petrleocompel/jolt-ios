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

    func testReturnsNilForNonPokeType() {
        let userInfo: [AnyHashable: Any] = ["type": "alarm", "alarmID": UUID().uuidString]
        XCTAssertNil(PokePushPayload(userInfo: userInfo))
    }

    func testReturnsNilForMalformedPokePayload() {
        let userInfo: [AnyHashable: Any] = ["type": "poke", "poke": ["senderHandle": "alice"]]
        XCTAssertNil(PokePushPayload(userInfo: userInfo))
    }
}
