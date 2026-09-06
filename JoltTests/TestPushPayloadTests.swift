import XCTest
@testable import Jolt

final class TestPushPayloadTests: XCTestCase {
    private func userInfo(stimulus: [String: Any]? = nil, testID: UUID, deviceID: UUID) -> [AnyHashable: Any] {
        var test: [String: Any] = [
            "testID": testID.uuidString,
            "deviceID": deviceID.uuidString,
            // The server sends these; the client ignores them, and must not
            // choke on them.
            "sentAt": "2026-09-07T10:15:00.000Z",
            "source": "web"
        ]
        if let stimulus { test["stimulus"] = stimulus }
        return ["type": "test", "test": test]
    }

    func testParsesNotificationOnlyTest() throws {
        let testID = UUID()
        let deviceID = UUID()

        let payload = try XCTUnwrap(TestPushPayload(userInfo: userInfo(testID: testID, deviceID: deviceID)))

        XCTAssertEqual(payload.testID, testID)
        XCTAssertEqual(payload.deviceID, deviceID)
        // No stimulus means nothing fires — the whole point of the default
        // test, which has to work with no Pavlok connected.
        XCTAssertNil(payload.stimulus)
    }

    func testParsesTestCarryingAStimulus() throws {
        let payload = try XCTUnwrap(TestPushPayload(userInfo: userInfo(
            stimulus: ["kind": "vibe", "intensity": 20, "repetitions": 2],
            testID: UUID(),
            deviceID: UUID()
        )))

        XCTAssertEqual(payload.stimulus?.kind, .vibe)
        XCTAssertEqual(payload.stimulus?.intensity, 20)
        XCTAssertEqual(payload.stimulus?.repetitions, 2)
    }

    func testIgnoresAPokePayload() {
        // The two payload types have to stay disjoint: a poke acks to a
        // different endpoint and does belong in the activity log.
        let userInfo: [AnyHashable: Any] = [
            "type": "poke",
            "poke": [
                "pokeID": UUID().uuidString,
                "senderHandle": "alice",
                "senderDisplayName": "Alice",
                "stimulus": ["kind": "zap", "intensity": 30, "repetitions": 1]
            ]
        ]
        XCTAssertNil(TestPushPayload(userInfo: userInfo))
    }

    func testIgnoresAlarmAndMalformedPayloads() {
        XCTAssertNil(TestPushPayload(userInfo: ["type": "alarm", "alarmID": UUID().uuidString]))
        XCTAssertNil(TestPushPayload(userInfo: ["type": "test", "test": ["testID": "not-a-uuid"]]))
        XCTAssertNil(TestPushPayload(userInfo: ["type": "test"]))
    }

    func testPokeParserIgnoresATestPayload() {
        XCTAssertNil(PokePushPayload(userInfo: userInfo(testID: UUID(), deviceID: UUID())))
    }
}
