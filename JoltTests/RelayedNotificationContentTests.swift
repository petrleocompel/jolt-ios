import CryptoKit
import XCTest
@testable import Jolt

/// What the Notification Service Extension does with a relayed alert:
/// replace the fallback text with the real one, or leave it alone.
final class RelayedNotificationContentTests: XCTestCase {
    /// UTC+2 on the vectors' date, so the local time is visibly not the
    /// server's.
    private let prague = TimeZone(identifier: "Europe/Prague")!
    private let britishEnglish = Locale(identifier: "en_GB")

    func testRewritesARelayedPokeInLocalTime() throws {
        let vectors = try EnvelopeVectors.load()
        let content = try XCTUnwrap(rewrite(relayed(vectors.case("poke")), key: vectors.key))

        XCTAssertEqual(content.title, "Alice")
        XCTAssertEqual(content.body, "zapped you — 30% x2 at 14:32")
    }

    func testRewritesARelayedTest() throws {
        let vectors = try EnvelopeVectors.load()
        let content = try XCTUnwrap(rewrite(relayed(vectors.case("test-with-stimulus")), key: vectors.key))

        XCTAssertEqual(content.title, "Jolt test")
        XCTAssertEqual(content.body, "Delivery works — firing vibe 50%, sent 14:33.")
    }

    /// The tap handler gets the decrypted poke, and still the envelope it was
    /// decrypted from.
    func testHandsTheDecryptedPayloadOnForTheTap() throws {
        let vectors = try EnvelopeVectors.load()
        let content = try XCTUnwrap(rewrite(relayed(vectors.case("poke")), key: vectors.key))

        XCTAssertEqual(PokePushPayload(userInfo: content.userInfo)?.senderHandle, "alice")
        XCTAssertNotNil(content.userInfo["enc"])
        XCTAssertEqual(content.userInfo["srv"] as? String, vectors.cases.first?.serverId)
    }

    func testLeavesTheFallbackWhenNoKeyIsHeld() throws {
        let vectors = try EnvelopeVectors.load()
        let content = RelayedNotificationContent(userInfo: try relayed(vectors.case("poke")), key: { _, _ in nil })

        XCTAssertNil(content)
    }

    func testLeavesTheFallbackWhenTheEnvelopeDoesNotOpen() throws {
        let vectors = try EnvelopeVectors.load()

        XCTAssertNil(rewrite(try relayed(vectors.case("poke"), type: "test"), key: vectors.key))
        XCTAssertNil(rewrite(try relayed(vectors.case("poke")), key: SymmetricKey(size: .bits256)))
    }

    func testLeavesADirectPushAlone() {
        let direct: [AnyHashable: Any] = [
            "aps": ["alert": ["title": "Alice", "body": "zapped you — 30% at 14:32 UTC"]],
            "type": "poke",
            "poke": ["pokeID": UUID().uuidString, "senderHandle": "alice", "senderDisplayName": "Alice",
                     "stimulus": ["kind": "zap", "intensity": 30, "repetitions": 1]]
        ]

        XCTAssertNil(rewrite(direct, key: SymmetricKey(size: .bits256)))
    }

    // MARK: - Alert text (port of jolt-server's alertTextFor / testAlertTextFor)

    func testPokeTextMarksAutomationAndFallsBackToTheHandle() {
        var poke = PokePushPayload(
            pokeID: UUID(), senderHandle: "alice", senderDisplayName: "", recipientHandle: "bob",
            stimulus: StimulusConfig(kind: .beep, intensity: 40), viaApiToken: true
        )
        XCTAssertEqual(text(poke), PushAlertText(title: "@alice", body: "beeped you — 40% (automation)"))

        poke.stimulus = StimulusConfig(kind: .vibe, intensity: 10, repetitions: 3)
        poke.sentAt = "2026-10-09T12:32:00Z"
        poke.viaApiToken = false
        XCTAssertEqual(text(poke).body, "buzzed you — 10% x3 at 14:32")
    }

    func testTimeFollowsThePhonesClockStyle() {
        let time = PushAlertText.sendTime(
            "2026-10-09T12:32:00.000Z", timeZone: prague, locale: Locale(identifier: "en_US")
        )
        XCTAssertEqual(time?.replacingOccurrences(of: "\u{202F}", with: " "), "2:32 PM")
    }

    /// A bad clock costs the time, not the notification.
    func testUnparseableTimeIsLeftOut() {
        XCTAssertNil(PushAlertText.sendTime("yesterday", timeZone: prague, locale: britishEnglish))
        let test = TestPushPayload(testID: UUID(), deviceID: UUID(), stimulus: nil, sentAt: "garbage")
        XCTAssertEqual(
            PushAlertText.test(test, timeZone: prague, locale: britishEnglish),
            PushAlertText(title: "Jolt", body: "Test notification — push delivery works.")
        )
    }

    // MARK: - Helpers

    private func relayed(_ vector: EnvelopeVectors.Case, type: String? = nil) -> [AnyHashable: Any] {
        [
            "aps": ["alert": ["title-loc-key": "PUSH_FALLBACK_TITLE", "loc-key": "PUSH_FALLBACK_POKE_BODY"],
                    "mutable-content": 1],
            "type": type ?? vector.kind,
            "srv": vector.serverId,
            "enc": vector.envelope
        ]
    }

    private func rewrite(_ userInfo: [AnyHashable: Any], key: SymmetricKey) -> RelayedNotificationContent? {
        RelayedNotificationContent(userInfo: userInfo, key: { _, _ in key }, timeZone: prague, locale: britishEnglish)
    }

    private func text(_ poke: PokePushPayload) -> PushAlertText {
        PushAlertText.poke(poke, timeZone: prague, locale: britishEnglish)
    }
}
