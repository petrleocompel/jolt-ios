import CryptoKit
import XCTest
@testable import Jolt

/// Opening a relayed push (`type` + `srv` + `enc`) into the `userInfo` the
/// poke and test parsers read, and every reason to refuse one.
final class RelayedPushTests: XCTestCase {
    private let serverId = "srv_kzdvvj2umnduyauf35o36k6kw4"

    // MARK: - Opening

    func testOpensARelayedPokeIntoWhatThePokeParserReads() throws {
        let vectors = try EnvelopeVectors.load()
        let opened = try open(relayedUserInfo(vectors.case("poke")), expecting: .relay(serverId: serverId), key: vectors.key)

        let poke = try XCTUnwrap(PokePushPayload(userInfo: opened))
        XCTAssertEqual(poke.pokeID, UUID(uuidString: "7d6f0c1e-2b3a-4c5d-8e9f-0a1b2c3d4e5f"))
        XCTAssertEqual(poke.senderDisplayName, "Alice")
        XCTAssertEqual(poke.recipientHandle, "bob")
        XCTAssertEqual(poke.stimulus, StimulusConfig(kind: .zap, intensity: 30, repetitions: 2))
        XCTAssertEqual(poke.serverId, serverId)
        XCTAssertEqual(poke.sentAt, "2026-10-09T12:32:00.000Z")
        XCTAssertEqual(poke.viaApiToken, false)
        XCTAssertNotNil(opened["enc"], "the envelope stays, so a later handler checks it again")
        XCTAssertNotNil(opened["aps"])
    }

    func testOpensARelayedTestIntoWhatTheTestParserReads() throws {
        let vectors = try EnvelopeVectors.load()
        let opened = try open(
            relayedUserInfo(vectors.case("test-with-stimulus")), expecting: .relay(serverId: serverId), key: vectors.key
        )

        let test = try XCTUnwrap(TestPushPayload(userInfo: opened))
        XCTAssertEqual(test.testID, UUID(uuidString: "3c2b1a09-8765-4321-a0b1-c2d3e4f5a6b7"))
        XCTAssertEqual(test.stimulus, StimulusConfig(kind: .vibe, intensity: 50, repetitions: 1))
        XCTAssertNil(PokePushPayload(userInfo: opened))
    }

    /// The relay can't read the poke, but it could put a plaintext one next
    /// to the envelope. The decrypted one must be what gets fired.
    func testTheDecryptedPokeWinsOverPlaintextBesideIt() throws {
        let vectors = try EnvelopeVectors.load()
        var userInfo = try relayedUserInfo(vectors.case("poke"))
        userInfo["poke"] = ["pokeID": UUID().uuidString, "senderHandle": "mallory", "senderDisplayName": "Mallory",
                            "stimulus": ["kind": "zap", "intensity": 100, "repetitions": 10]]

        let opened = try open(userInfo, expecting: .relay(serverId: serverId), key: vectors.key)

        XCTAssertEqual(PokePushPayload(userInfo: opened)?.senderHandle, "alice")
    }

    // MARK: - Refusing

    func testRefusesAnOuterTypeTheEnvelopeWasNotSealedFor() throws {
        let vectors = try EnvelopeVectors.load()
        let userInfo = try relayedUserInfo(vectors.case("poke"), type: "test")

        XCTAssertEqual(failure(userInfo, key: vectors.key), .envelope(.authenticationFailed))
    }

    func testRefusesAnOuterServerTheEnvelopeWasNotSealedFor() throws {
        let vectors = try EnvelopeVectors.load()
        let other = "srv_aaaaaaaaaaaaaaaaaaaaaaaaaa"
        let userInfo = try relayedUserInfo(vectors.case("poke"), srv: other)

        XCTAssertEqual(failure(userInfo, expecting: .anyKeyedServer, key: vectors.key), .envelope(.authenticationFailed))
    }

    func testRefusesAPlaintextTypeThatDisagreesWithTheOuterOne() throws {
        let key = SymmetricKey(size: .bits256)
        let userInfo = try sealed(
            #"{"type":"test","poke":{"serverId":"srv_kzdvvj2umnduyauf35o36k6kw4"}}"#, kind: "poke", key: key
        )

        XCTAssertEqual(failure(userInfo, key: key), .typeMismatch)
    }

    func testRefusesAPlaintextNamingAnotherServer() throws {
        let key = SymmetricKey(size: .bits256)
        let userInfo = try sealed(#"{"type":"poke","poke":{"serverId":"srv_aaaaaaaaaaaaaaaaaaaaaaaaaa"}}"#, kind: "poke", key: key)

        XCTAssertEqual(failure(userInfo, key: key), .serverMismatch)
    }

    func testRefusesAPlaintextNamingNoServer() throws {
        let key = SymmetricKey(size: .bits256)
        let userInfo = try sealed(#"{"type":"poke","poke":{"pokeID":"x"}}"#, kind: "poke", key: key)

        XCTAssertEqual(failure(userInfo, key: key), .serverMismatch)
    }

    func testRefusesAServerOtherThanTheRegisteredOne() throws {
        let vectors = try EnvelopeVectors.load()
        let userInfo = try relayedUserInfo(vectors.case("poke"))

        XCTAssertEqual(
            failure(userInfo, expecting: .relay(serverId: "srv_aaaaaaaaaaaaaaaaaaaaaaaaaa"), key: vectors.key),
            .serverMismatch
        )
    }

    func testRefusesARelayedPushWhenNotRegisteredThroughTheRelay() throws {
        let vectors = try EnvelopeVectors.load()

        XCTAssertEqual(failure(try relayedUserInfo(vectors.case("poke")), expecting: .direct, key: vectors.key), .serverMismatch)
    }

    func testRefusesAServerWithNoKey() throws {
        let vectors = try EnvelopeVectors.load()
        let result = RelayedPush.open(try relayedUserInfo(vectors.case("poke")), expecting: .anyKeyedServer) { _ in nil }

        XCTAssertEqual(result.failure, .unknownServer)
    }

    func testRefusesAnEnvelopeWithoutAServer() throws {
        let vectors = try EnvelopeVectors.load()
        var userInfo = try relayedUserInfo(vectors.case("poke"))
        userInfo.removeValue(forKey: "srv")

        XCTAssertEqual(failure(userInfo, expecting: .anyKeyedServer, key: vectors.key), .malformed)
    }

    func testRefusesAPlaintextPokeWhenRegisteredThroughTheRelay() {
        let userInfo: [AnyHashable: Any] = ["type": "poke", "poke": ["pokeID": UUID().uuidString]]

        XCTAssertEqual(failure(userInfo, expecting: .relay(serverId: serverId), key: SymmetricKey(size: .bits256)), .missingEnvelope)
    }

    // MARK: - Passing through

    func testPassesADirectPushThroughWhenNotRegisteredThroughTheRelay() throws {
        let userInfo: [AnyHashable: Any] = ["type": "poke", "poke": ["pokeID": "x"]]

        let opened = try open(userInfo, expecting: .direct, key: SymmetricKey(size: .bits256))

        XCTAssertEqual(opened["type"] as? String, "poke")
    }

    func testPassesSomethingThatIsNotAPokeOrTestThrough() throws {
        let userInfo: [AnyHashable: Any] = ["alarmID": UUID().uuidString]

        XCTAssertNoThrow(try open(userInfo, expecting: .relay(serverId: serverId), key: SymmetricKey(size: .bits256)))
    }

    // MARK: - Helpers

    private func relayedUserInfo(
        _ vector: EnvelopeVectors.Case, type: String? = nil, srv: String? = nil
    ) -> [AnyHashable: Any] {
        [
            "aps": ["alert": ["title-loc-key": "PUSH_FALLBACK_TITLE", "loc-key": "PUSH_FALLBACK_POKE_BODY"],
                    "mutable-content": 1, "sound": "default"],
            "type": type ?? vector.kind,
            "srv": srv ?? vector.serverId,
            "enc": vector.envelope
        ]
    }

    private func sealed(_ plaintext: String, kind: String, key: SymmetricKey) throws -> [AnyHashable: Any] {
        let envelope = try PushEnvelope.seal(Data(plaintext.utf8), with: key, serverId: serverId, kind: kind)
        return ["type": kind, "srv": serverId, "enc": envelope.jsonObject]
    }

    private func open(
        _ userInfo: [AnyHashable: Any], expecting: RelayedPush.Expectation, key: SymmetricKey
    ) throws -> [AnyHashable: Any] {
        try RelayedPush.open(userInfo, expecting: expecting) { $0 == self.serverId ? key : nil }.get()
    }

    private func failure(
        _ userInfo: [AnyHashable: Any], expecting: RelayedPush.Expectation? = nil, key: SymmetricKey
    ) -> RelayedPush.Failure? {
        RelayedPush.open(userInfo, expecting: expecting ?? .relay(serverId: serverId)) { _ in key }.failure
    }
}

extension Result {
    var failure: Failure? {
        if case .failure(let failure) = self { return failure }
        return nil
    }
}
