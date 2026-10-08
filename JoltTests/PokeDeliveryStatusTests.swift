import XCTest
@testable import Jolt

final class PokeDeliveryStatusTests: XCTestCase {
    func testDecodesEveryStatusTheServerCanSend() throws {
        // The server added `pending` after this enum was written; decoding a
        // real PokeEvent would have thrown without it.
        for raw in ["pending", "fired", "deviceNotConnected", "notAllowed", "muted"] {
            let decoded = try JSONDecoder().decode(
                PokeDeliveryStatus.self, from: Data("\"\(raw)\"".utf8)
            )
            XCTAssertEqual(decoded.rawValue, raw)
        }
    }

    func testDecodesAPokeEventAsTheServerSerialisesIt() throws {
        let json = """
        {
          "id": "8B1E4B8E-3E4E-4C0E-9B3E-2A1B4C5D6E7F",
          "direction": "received",
          "friendHandle": "alice",
          "friendDisplayName": "Alice",
          "stimulus": { "kind": "vibe", "intensity": 40, "repetitions": 2 },
          "status": "pending",
          "createdAt": "2026-08-29T10:15:30.123Z"
        }
        """
        let event = try JSONDecoder.joltTesting.decode(PokeEvent.self, from: Data(json.utf8))
        XCTAssertEqual(event.status, .pending)
        XCTAssertEqual(event.stimulus.kind, .vibe)
        XCTAssertEqual(event.friendHandle, "alice")
    }

    func testDecodesTimestampsWithAndWithoutFractionalSeconds() throws {
        // The server emits both forms depending on the column.
        for stamp in ["2026-08-29T10:15:30Z", "2026-08-29T10:15:30.123Z"] {
            let json = """
            { "id": "8B1E4B8E-3E4E-4C0E-9B3E-2A1B4C5D6E7F", "direction": "sent",
              "friendHandle": "a", "friendDisplayName": "A",
              "stimulus": { "kind": "zap", "intensity": 1, "repetitions": 1 },
              "status": "fired", "createdAt": "\(stamp)" }
            """
            XCTAssertNoThrow(try JSONDecoder.joltTesting.decode(PokeEvent.self, from: Data(json.utf8)),
                             "failed to decode \(stamp)")
        }
    }

    func testDecodesAPokeSentByAScript() throws {
        let json = """
        { "id": "8B1E4B8E-3E4E-4C0E-9B3E-2A1B4C5D6E7F", "direction": "sent",
          "friendHandle": "a", "friendDisplayName": "A",
          "stimulus": { "kind": "zap", "intensity": 1, "repetitions": 1 },
          "status": "fired", "createdAt": "2026-08-29T10:15:30Z", "ackedAt": null,
          "viaApiToken": true, "apiTokenName": "home assistant" }
        """
        let event = try JSONDecoder.joltTesting.decode(PokeEvent.self, from: Data(json.utf8))
        XCTAssertTrue(event.isAutomated)
        XCTAssertEqual(event.apiTokenName, "home assistant")
    }

    /// The recipient's view: flagged as automated, but the token's name is
    /// the sender's business.
    func testDecodesAReceivedScriptedPokeWithoutATokenName() throws {
        let json = """
        { "id": "8B1E4B8E-3E4E-4C0E-9B3E-2A1B4C5D6E7F", "direction": "received",
          "friendHandle": "a", "friendDisplayName": "A",
          "stimulus": { "kind": "zap", "intensity": 1, "repetitions": 1 },
          "status": "fired", "createdAt": "2026-08-29T10:15:30Z",
          "viaApiToken": true, "apiTokenName": null }
        """
        let event = try JSONDecoder.joltTesting.decode(PokeEvent.self, from: Data(json.utf8))
        XCTAssertTrue(event.isAutomated)
        XCTAssertNil(event.apiTokenName)
    }

    /// A server that predates the keys: every poke was sent in person.
    func testAPokeWithoutTheAutomationKeysIsNotAutomated() throws {
        let json = """
        { "id": "8B1E4B8E-3E4E-4C0E-9B3E-2A1B4C5D6E7F", "direction": "sent",
          "friendHandle": "a", "friendDisplayName": "A",
          "stimulus": { "kind": "zap", "intensity": 1, "repetitions": 1 },
          "status": "fired", "createdAt": "2026-08-29T10:15:30Z" }
        """
        let event = try JSONDecoder.joltTesting.decode(PokeEvent.self, from: Data(json.utf8))
        XCTAssertFalse(event.isAutomated)
        XCTAssertNil(event.viaApiToken)
        XCTAssertNil(event.apiTokenName)
    }
}

private extension JSONDecoder {
    /// Mirrors the strategy `JoltAPIClient` installs, so these tests exercise
    /// the same date handling the real client uses.
    static var joltTesting: JSONDecoder {
        let decoder = JSONDecoder()
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = withFraction.date(from: text) ?? plain.date(from: text) { return date }
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Unrecognised date: \(text)")
            )
        }
        return decoder
    }
}
