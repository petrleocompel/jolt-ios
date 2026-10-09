import CryptoKit
import XCTest
@testable import Jolt

/// The relay protocol's envelope, against its normative vectors
/// (`RelayVectors/envelope-v1.json`, copied from jolt-relay). If one of these
/// fails, the app can't open what a conforming server seals.
final class PushEnvelopeTests: XCTestCase {
    func testKeyIDMatchesTheVector() throws {
        let vectors = try EnvelopeVectors.load()
        XCTAssertEqual(PushEnvelope.keyID(for: vectors.key), vectors.kid)
    }

    func testOpensEveryPositiveVector() throws {
        let vectors = try EnvelopeVectors.load()
        XCTAssertFalse(vectors.cases.isEmpty)
        for vector in vectors.cases {
            XCTAssertEqual(
                String(decoding: PushEnvelope.additionalData(serverId: vector.serverId, kind: vector.kind), as: UTF8.self),
                vector.aad,
                vector.name
            )
            let envelope = try XCTUnwrap(PushEnvelope(vector.envelope), vector.name)
            let plaintext = try envelope.open(with: vectors.key, serverId: vector.serverId, kind: vector.kind)
            XCTAssertEqual(String(decoding: plaintext, as: UTF8.self), vector.plaintext, vector.name)
        }
    }

    /// GCM is deterministic for a given nonce, so sealing the vector's
    /// plaintext with its nonce must give back its ciphertext byte for byte.
    func testSealingReproducesEveryPositiveVector() throws {
        let vectors = try EnvelopeVectors.load()
        for vector in vectors.cases {
            let expected = try XCTUnwrap(PushEnvelope(vector.envelope), vector.name)
            let sealed = try PushEnvelope.seal(
                Data(vector.plaintext.utf8), with: vectors.key,
                serverId: vector.serverId, kind: vector.kind,
                nonce: AES.GCM.Nonce(data: expected.nonce)
            )
            XCTAssertEqual(sealed, expected, vector.name)
        }
    }

    func testRefusesEveryNegativeVector() throws {
        let vectors = try EnvelopeVectors.load()
        XCTAssertFalse(vectors.negative.isEmpty)
        for vector in vectors.negative {
            XCTAssertEqual(vector.expect, "decrypt-fails", vector.name)
            let source = try XCTUnwrap(vectors.cases.first { $0.name == vector.envelopeOf }, vector.name)
            let envelope = try XCTUnwrap(PushEnvelope(source.envelope), vector.name)
            XCTAssertThrowsError(
                try envelope.open(
                    with: vectors.key,
                    serverId: vector.serverId ?? source.serverId,
                    kind: vector.kind ?? source.kind
                ),
                vector.name
            ) { error in
                XCTAssertEqual(error as? PushEnvelope.OpenError, .authenticationFailed, vector.name)
            }
        }
    }

    func testRefusesAnotherKeyBeforeTryingIt() throws {
        let vectors = try EnvelopeVectors.load()
        let source = try XCTUnwrap(vectors.cases.first)
        let envelope = try XCTUnwrap(PushEnvelope(source.envelope))

        XCTAssertThrowsError(
            try envelope.open(with: SymmetricKey(size: .bits256), serverId: source.serverId, kind: source.kind)
        ) { error in
            XCTAssertEqual(error as? PushEnvelope.OpenError, .keyMismatch)
        }
    }

    func testRefusesATamperedCiphertext() throws {
        let vectors = try EnvelopeVectors.load()
        let source = try XCTUnwrap(vectors.cases.first)
        var envelope = try XCTUnwrap(PushEnvelope(source.envelope))
        envelope.ciphertext[0] ^= 0x01

        XCTAssertThrowsError(
            try envelope.open(with: vectors.key, serverId: source.serverId, kind: source.kind)
        ) { error in
            XCTAssertEqual(error as? PushEnvelope.OpenError, .authenticationFailed)
        }
    }

    func testParsesOnlyWellFormedVersionOneEnvelopes() throws {
        let vectors = try EnvelopeVectors.load()
        let good = try XCTUnwrap(vectors.cases.first?.envelope)
        XCTAssertNotNil(PushEnvelope(good))

        var wrongVersion = good
        wrongVersion["v"] = 2
        XCTAssertNil(PushEnvelope(wrongVersion))

        var shortNonce = good
        shortNonce["n"] = Base64URL.encode(Data(count: 8))
        XCTAssertNil(PushEnvelope(shortNonce))

        var noTag = good
        noTag["ct"] = Base64URL.encode(Data(count: 15))
        XCTAssertNil(PushEnvelope(noTag))

        var paddedBase64 = good
        paddedBase64["n"] = Data(count: 12).base64EncodedString() + "="
        XCTAssertNil(PushEnvelope(paddedBase64))

        XCTAssertNil(PushEnvelope("not an object"))
    }

    func testBase64URLRoundTripsWithoutPadding() throws {
        for length in 0..<40 {
            let data = Data((0..<length).map { UInt8(truncatingIfNeeded: $0 &* 37 &+ 250) })
            let encoded = Base64URL.encode(data)
            XCTAssertFalse(encoded.contains { "+/=".contains($0) })
            XCTAssertEqual(Base64URL.decode(encoded), data)
        }
        XCTAssertNil(Base64URL.decode("AAECAw=="), "padding is not base64url as the protocol spells it")
        XCTAssertNil(Base64URL.decode("a+b/"), "standard base64 alphabet")
        XCTAssertNil(Base64URL.decode("A"), "no valid encoding is 1 mod 4 long")
    }
}

/// `RelayVectors/envelope-v1.json`, decoded.
struct EnvelopeVectors {
    struct Case {
        var name: String
        var kind: String
        var serverId: String
        var aad: String
        var plaintext: String
        var envelope: [String: Any]
    }

    struct Negative {
        var name: String
        var envelopeOf: String
        var kind: String?
        var serverId: String?
        var expect: String
    }

    var key: SymmetricKey
    var kid: String
    var cases: [Case]
    var negative: [Negative]

    static func load() throws -> EnvelopeVectors {
        let url = try XCTUnwrap(
            Bundle(for: PushEnvelopeTests.self).url(forResource: "envelope-v1", withExtension: "json"),
            "envelope-v1.json is missing from the test bundle"
        )
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let keyData = try XCTUnwrap((root["keyB64u"] as? String).flatMap(Base64URL.decode))
        let cases = try XCTUnwrap(root["cases"] as? [[String: Any]]).map { item in
            Case(
                name: try XCTUnwrap(item["name"] as? String),
                kind: try XCTUnwrap(item["kind"] as? String),
                serverId: try XCTUnwrap(item["serverId"] as? String),
                aad: try XCTUnwrap(item["aad"] as? String),
                plaintext: try XCTUnwrap(item["plaintext"] as? String),
                envelope: try XCTUnwrap(item["envelope"] as? [String: Any])
            )
        }
        let negative = try XCTUnwrap(root["negative"] as? [[String: Any]]).map { item in
            Negative(
                name: try XCTUnwrap(item["name"] as? String),
                envelopeOf: try XCTUnwrap(item["envelopeOf"] as? String),
                kind: item["kind"] as? String,
                serverId: item["serverId"] as? String,
                expect: try XCTUnwrap(item["expect"] as? String)
            )
        }
        return EnvelopeVectors(
            key: SymmetricKey(data: keyData),
            kid: try XCTUnwrap(root["kid"] as? String),
            cases: cases,
            negative: negative
        )
    }

    func `case`(_ name: String) throws -> Case {
        try XCTUnwrap(cases.first { $0.name == name }, "no vector named \(name)")
    }
}
