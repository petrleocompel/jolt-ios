import CryptoKit
import XCTest
@testable import Jolt

/// Which way this phone registers for pushes — directly, through the relay,
/// or not at all — as the server's `GET /push/config` decides, and keeping
/// that registration in step with the session.
@MainActor
final class PushRegistrationTests: XCTestCase {
    private let configuration = ServerConfiguration(baseURL: URL(string: "https://unit-test.invalid/api/v1")!)
    private let serverId = "srv_kzdvvj2umnduyauf35o36k6kw4"
    private let apnsToken = "a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90"
    private let keys = PayloadKeyStore(service: "cz.peelco.jolt.tests.payloadKey")
    private let registrations = RelayRegistrationStore(service: "cz.peelco.jolt.tests.relayRegistration")
    private let relayConfig = """
    {"transport":"relay","relay":{"url":"https://relay.example/","serverId":"srv_kzdvvj2umnduyauf35o36k6kw4"}}
    """

    private let backoffDefaults = UserDefaults(suiteName: "cz.peelco.jolt.tests.relayBackoff")!
    private var clock = Date()

    override func tearDown() {
        AuthTokenStore().clear(for: configuration)
        keys.remove(for: serverId)
        registrations.clear()
        for pending in registrations.pendingUnregistrations() {
            registrations.removePendingUnregistration(relayToken: pending.relayToken)
        }
        backoffDefaults.removePersistentDomain(forName: "cz.peelco.jolt.tests.relayBackoff")
        StubURLProtocol.handler = nil
        StubURLProtocol.headers = nil
        super.tearDown()
    }

    // MARK: - Choosing the transport

    func testRegistersThroughATrustedRelay() async throws {
        let stub = PushStub(pushConfig: (200, relayConfig))
        let backend = try await signedInBackend(stub)

        await backend.registerPushToken(apnsToken)

        let relayRequest = try XCTUnwrap(stub.relayRegistrations.first?.body)
        XCTAssertEqual(relayRequest["platform"] as? String, "ios")
        XCTAssertEqual(relayRequest["provider"] as? String, "apns")
        XCTAssertEqual(relayRequest["token"] as? String, apnsToken)
        XCTAssertEqual(relayRequest["environment"] as? String, "sandbox")
        XCTAssertEqual(relayRequest["appId"] as? String, "cz.peelco.jolt")
        XCTAssertEqual(relayRequest["serverId"] as? String, serverId)

        let serverRequest = try XCTUnwrap(stub.requests("POST", "/devices/push-token").first?.body)
        XCTAssertEqual(serverRequest["transport"] as? String, "relay")
        XCTAssertEqual(serverRequest["platform"] as? String, "ios")
        XCTAssertEqual(serverRequest["relayToken"] as? String, "rt_issued1")
        XCTAssertNil(serverRequest["token"], "the server must never see the APNs token")

        let key = try XCTUnwrap(keys.currentKey(for: serverId), "the payload key must be kept for the extension")
        let sentKey = try XCTUnwrap((serverRequest["payloadKey"] as? String).flatMap(Base64URL.decode))
        XCTAssertEqual(sentKey, key.withUnsafeBytes { Data($0) })
        XCTAssertEqual(serverRequest["keyId"] as? String, PushEnvelope.keyID(for: key))

        XCTAssertEqual(backend.pushRegistration.transport, .relay(serverId: serverId))
        XCTAssertEqual(backend.pushRegistration.registeredToken, "rt_issued1")
        XCTAssertNil(backend.pushRegistration.problem)
    }

    /// A server that predates `/push/config` answers 404, and gets exactly
    /// the registration every earlier build sent.
    func testRegistersDirectlyWithAServerThatPredatesPushConfig() async throws {
        let stub = PushStub(pushConfig: (404, #"{"message":"Route GET:/api/v1/push/config not found"}"#))
        let backend = try await signedInBackend(stub)

        await backend.registerPushToken(apnsToken)

        try assertRegisteredDirectly(stub, backend)
    }

    func testRegistersDirectlyWhenTheServerHasItsOwnAPNsCredentials() async throws {
        let stub = PushStub(pushConfig: (200, #"{"transport":"apns","apnsEnvironment":"production"}"#))
        let backend = try await signedInBackend(stub)

        await backend.registerPushToken(apnsToken)

        try assertRegisteredDirectly(stub, backend)
    }

    func testRegistersNothingWhenTheServerHasNoPush() async throws {
        let stub = PushStub(pushConfig: (200, #"{"transport":"none"}"#))
        let backend = try await signedInBackend(stub)

        await backend.registerPushToken(apnsToken)

        XCTAssertTrue(stub.requests("POST", "/devices/push-token").isEmpty)
        XCTAssertEqual(backend.pushRegistration.transport, .none)
    }

    func testRefusesARelayThatIsNotOnTheAllowList() async throws {
        let stub = PushStub(pushConfig: (200, relayConfig))
        let backend = try await signedInBackend(stub, trustedHosts: TrustedRelayHosts(["other.example"]))

        await backend.registerPushToken(apnsToken)

        XCTAssertTrue(stub.requests(nil, "relay.example").isEmpty, "the APNs token must not reach an untrusted relay")
        XCTAssertTrue(stub.requests("POST", "/devices/push-token").isEmpty)
        XCTAssertEqual(backend.pushRegistration.transport, .relay(serverId: serverId))
        XCTAssertNil(backend.pushRegistration.registeredToken)
        XCTAssertNotNil(backend.pushRegistration.problem)
    }

    /// The server names a relay this build doesn't trust: refuse it, but keep
    /// the registration that already works rather than revoking it (C18).
    func testAnUntrustedRelayLeavesTheWorkingRegistrationAlone() async throws {
        let stub = PushStub(pushConfig: (200, relayConfig))
        let backend = try await signedInBackend(stub)
        await backend.registerPushToken(apnsToken)
        let key = try XCTUnwrap(keys.currentKey(for: serverId))

        stub.pushConfig = (200, relayConfig.replacingOccurrences(of: "relay.example", with: "untrusted.example"))
        await backend.registerLastPushToken()

        XCTAssertTrue(stub.relayUnregistrations.isEmpty)
        XCTAssertTrue(stub.forgottenRelayTokens.isEmpty)
        XCTAssertTrue(stub.requests(nil, "untrusted.example").isEmpty)
        XCTAssertEqual(registrations.load()?.relayToken, "rt_issued1")
        XCTAssertEqual(keys.currentKey(for: serverId).map(PushEnvelope.keyID(for:)), PushEnvelope.keyID(for: key))
        XCTAssertEqual(backend.pushRegistration.registeredToken, "rt_issued1")
        XCTAssertNotNil(backend.pushRegistration.problem)
    }

    /// Offline, or the server is down: keep what was registered rather than
    /// guessing at a transport.
    func testLeavesTheRegistrationAloneWhenPushConfigCannotBeFetched() async throws {
        let stub = PushStub(pushConfig: (503, #"{"message":"down"}"#))
        let backend = try await signedInBackend(stub)

        await backend.registerPushToken(apnsToken)

        XCTAssertTrue(stub.requests("POST", "/devices/push-token").isEmpty)
        XCTAssertEqual(backend.pushRegistration.transport, .unknown)
        XCTAssertNotNil(backend.pushRegistration.problem)
    }

    // MARK: - App Attest

    func testRegistersWithoutAttestationWhereAppAttestIsUnavailable() async throws {
        let stub = PushStub(pushConfig: (200, relayConfig))
        let backend = try await signedInBackend(stub, attestor: FakeAttestor(isSupported: false))

        await backend.registerPushToken(apnsToken)

        XCTAssertTrue(stub.requests("GET", "/v1/challenge").isEmpty)
        let body = try XCTUnwrap(stub.relayRegistrations.first?.body)
        XCTAssertNil(body["attestation"])
        XCTAssertEqual(backend.pushRegistration.registeredToken, "rt_issued1")
    }

    func testAttestsTheFirstRegistrationAndAssertsLaterOnes() async throws {
        let stub = PushStub(pushConfig: (200, relayConfig))
        let attestor = FakeAttestor(isSupported: true)
        let backend = try await signedInBackend(stub, attestor: attestor)

        await backend.registerPushToken(apnsToken)
        await backend.reregisterPush()

        let bodies = stub.relayRegistrations.compactMap { $0.body?["attestation"] as? [String: Any] }
        XCTAssertEqual(bodies.count, 2)
        XCTAssertEqual(bodies[0]["type"] as? String, "apple-app-attest")
        XCTAssertEqual(bodies[0]["challenge"] as? String, "Y2hhbGxlbmdlLTE")
        XCTAssertEqual(bodies[0]["keyId"] as? String, "key-1")
        XCTAssertEqual(bodies[0]["attestationObject"] as? String, Data("attestation".utf8).base64EncodedString())
        XCTAssertNil(bodies[0]["assertion"])
        XCTAssertNil(bodies[1]["attestationObject"])
        XCTAssertEqual(bodies[1]["assertion"] as? String, Data("assertion".utf8).base64EncodedString())

        let expectedHash = Data(SHA256.hash(data: Data("jolt-relay-v1|Y2hhbGxlbmdlLTE|\(apnsToken)|\(serverId)".utf8)))
        XCTAssertEqual(attestor.hashes.first, expectedHash)
    }

    // MARK: - Keeping it in step

    func testReassertsAnExistingRelayRegistrationWithoutRegisteringAgain() async throws {
        let stub = PushStub(pushConfig: (200, relayConfig))
        let backend = try await signedInBackend(stub)

        await backend.registerPushToken(apnsToken)
        await backend.registerLastPushToken()

        XCTAssertEqual(stub.relayRegistrations.count, 1)
        let tokens = stub.requests("POST", "/devices/push-token").map { $0.body?["relayToken"] as? String }
        XCTAssertEqual(tokens, ["rt_issued1", "rt_issued1"])
    }

    func testRegistersAgainWhenApplesTokenChanges() async throws {
        let stub = PushStub(pushConfig: (200, relayConfig))
        let backend = try await signedInBackend(stub)

        await backend.registerPushToken(apnsToken)
        await backend.registerPushToken("ffff")

        let relayTokens = stub.relayRegistrations.map { $0.body?["token"] as? String }
        XCTAssertEqual(relayTokens, [apnsToken, "ffff"])
        XCTAssertEqual(stub.relayUnregistrations, ["rt_issued1"])
        XCTAssertEqual(backend.pushRegistration.registeredToken, "rt_issued2")
    }

    /// The server moved from the relay to its own credentials: the relay
    /// registration is revoked everywhere before the direct one is made.
    func testMovingOffTheRelayRevokesItsRegistration() async throws {
        let stub = PushStub(pushConfig: (200, relayConfig))
        let backend = try await signedInBackend(stub)
        await backend.registerPushToken(apnsToken)

        stub.pushConfig = (200, #"{"transport":"apns","apnsEnvironment":"production"}"#)
        await backend.registerLastPushToken()

        XCTAssertEqual(stub.forgottenRelayTokens, ["rt_issued1"])
        XCTAssertEqual(stub.relayUnregistrations, ["rt_issued1"])
        XCTAssertNil(keys.currentKey(for: serverId))
        XCTAssertNil(registrations.load())
        XCTAssertEqual(stub.requests("POST", "/devices/push-token").last?.body?["token"] as? String, apnsToken)
    }

    /// An ack the server 404s means this phone fired a poke meant for
    /// another account. A fresh relay token cuts that account off.
    func testAPokeThatWasNotOursRegistersThroughTheRelayAfresh() async throws {
        let stub = PushStub(pushConfig: (200, relayConfig))
        stub.ackStatus = 404
        let backend = try await signedInBackend(stub)
        await backend.registerPushToken(apnsToken)

        await backend.handleIncomingPoke(PokePushPayload(
            pokeID: UUID(), senderHandle: "alice", senderDisplayName: "Alice",
            recipientHandle: nil, stimulus: StimulusConfig(kind: .vibe)
        ))

        XCTAssertEqual(stub.relayRegistrations.count, 2)
        XCTAssertEqual(stub.relayUnregistrations, ["rt_issued1"])
        XCTAssertEqual(backend.pushRegistration.registeredToken, "rt_issued2")
    }

    func testSigningOutRevokesTheRelayRegistrationAndForgetsTheKey() async throws {
        let stub = PushStub(pushConfig: (200, relayConfig))
        let backend = try await signedInBackend(stub)
        await backend.registerPushToken(apnsToken)

        await backend.logOut()

        XCTAssertEqual(stub.forgottenRelayTokens, ["rt_issued1"])
        XCTAssertEqual(stub.relayUnregistrations, ["rt_issued1"])
        XCTAssertNil(keys.currentKey(for: serverId))
        XCTAssertNil(registrations.load())
        XCTAssertEqual(backend.pushRegistration, PushRegistrationState())
    }

    /// A registration made for the server the user has since switched away
    /// from is revoked at the relay as soon as the app starts. The old server
    /// can't be told — this session can't sign in to it — so the relay is
    /// what cuts it off.
    func testARegistrationForAnotherServerIsRevokedAtTheRelay() async throws {
        let oldKey = SymmetricKey(size: .bits256)
        keys.save(oldKey, for: "srv_aaaaaaaaaaaaaaaaaaaaaaaaaa")
        defer { keys.remove(for: "srv_aaaaaaaaaaaaaaaaaaaaaaaaaa") }
        registrations.save(RelayRegistration(
            serverBaseURL: URL(string: "https://old.invalid/api/v1")!, relayURL: URL(string: "https://relay.example/")!,
            serverId: "srv_aaaaaaaaaaaaaaaaaaaaaaaaaa", relayToken: "rt_old", apnsToken: apnsToken,
            keyId: PushEnvelope.keyID(for: oldKey)
        ))
        let stub = PushStub(pushConfig: (200, relayConfig))

        // Signing in waits for the launch-time revocation queued before it.
        let backend = try await signedInBackend(stub)

        XCTAssertEqual(stub.relayUnregistrations, ["rt_old"])
        XCTAssertTrue(stub.requests("DELETE", "/devices/push-token").isEmpty)
        XCTAssertNil(keys.currentKey(for: "srv_aaaaaaaaaaaaaaaaaaaaaaaaaa"))
        XCTAssertNil(registrations.load())

        await backend.registerPushToken(apnsToken)

        XCTAssertEqual(registrations.load()?.serverId, serverId)
    }

    /// Every new relay token comes with a new key, and the one it replaces
    /// keeps opening pushes for a day: the server may have sealed some just
    /// before it heard of the new one (C8).
    func testANewRelayTokenComesWithANewKeyAndKeepsThePreviousOne() async throws {
        let stub = PushStub(pushConfig: (200, relayConfig))
        let backend = try await signedInBackend(stub)
        await backend.registerPushToken(apnsToken)
        let oldKey = try XCTUnwrap(keys.currentKey(for: serverId))

        await backend.reregisterPush()

        let newKey = try XCTUnwrap(keys.currentKey(for: serverId))
        XCTAssertNotEqual(PushEnvelope.keyID(for: newKey), PushEnvelope.keyID(for: oldKey))
        XCTAssertEqual(registrations.load()?.keyId, PushEnvelope.keyID(for: newKey))
        let sentKeys = stub.requests("POST", "/devices/push-token").compactMap { $0.body?["payloadKey"] as? String }
        XCTAssertEqual(sentKeys.count, 2)
        XCTAssertNotEqual(sentKeys[0], sentKeys[1])

        let inFlight = try sealedPoke(with: oldKey)
        XCTAssertNotNil(backend.openIncomingPush(inFlight), "a push sealed with the previous key still opens")
        XCTAssertNotNil(backend.openIncomingPush(try sealedPoke(with: newKey)))
    }

    /// The server says the relay dropped this registration. Token and key
    /// both go, and a fresh registration takes their place (C6).
    func testRecoversFromARevokedRelayToken() async throws {
        let stub = PushStub(pushConfig: (200, relayConfig))
        let backend = try await signedInBackend(stub)
        await backend.registerPushToken(apnsToken)
        let oldKey = try XCTUnwrap(keys.currentKey(for: serverId))

        stub.revoke("rt_issued1")
        await backend.registerLastPushToken()

        XCTAssertEqual(stub.relayRegistrations.count, 2)
        XCTAssertEqual(stub.relayUnregistrations, ["rt_issued1"])
        XCTAssertEqual(stub.forgottenRelayTokens, ["rt_issued1"])
        let posted = stub.requests("POST", "/devices/push-token").map { $0.body?["relayToken"] as? String }
        XCTAssertEqual(posted, ["rt_issued1", "rt_issued1", "rt_issued2"])
        XCTAssertEqual(backend.pushRegistration.registeredToken, "rt_issued2")
        XCTAssertNil(backend.pushRegistration.problem)
        XCTAssertNil(
            keys.key(for: serverId, kid: PushEnvelope.keyID(for: oldKey)),
            "a revoked registration's key is discarded, not kept for a day"
        )
        XCTAssertNotNil(keys.currentKey(for: serverId))
    }

    /// Tries once. A server that keeps refusing doesn't get a loop.
    func testGivesUpWhenEvenAFreshRelayTokenIsRefusedAsRevoked() async throws {
        let stub = PushStub(pushConfig: (200, relayConfig))
        let backend = try await signedInBackend(stub)
        stub.revoke("rt_issued1")
        stub.revoke("rt_issued2")

        await backend.registerPushToken(apnsToken)

        XCTAssertEqual(stub.relayRegistrations.count, 2)
        XCTAssertNotNil(backend.pushRegistration.problem)
    }

    /// The server moved from its own credentials to the relay: the direct
    /// registration goes, or the phone would get every poke twice (C7).
    func testMovingOntoTheRelayForgetsTheDirectRegistration() async throws {
        let stub = PushStub(pushConfig: (200, #"{"transport":"apns","apnsEnvironment":"production"}"#))
        let backend = try await signedInBackend(stub)
        await backend.registerPushToken(apnsToken)

        stub.pushConfig = (200, relayConfig)
        await backend.registerLastPushToken()

        XCTAssertEqual(stub.forgottenAPNsTokens, [apnsToken])
        XCTAssertEqual(stub.relayRegistrations.count, 1)
        XCTAssertEqual(backend.pushRegistration.transport, .relay(serverId: serverId))
    }

    /// A relay URL may carry a path prefix, with or without the trailing
    /// slash, and either spelling is the same relay (C1).
    func testResolvesRelayPathsUnderAPathPrefix() async throws {
        let config = #"{"transport":"relay","relay":{"url":"https://relay.example/jolt","serverId":"\#(serverId)"}}"#
        let stub = PushStub(pushConfig: (200, config))
        let backend = try await signedInBackend(stub)

        await backend.registerPushToken(apnsToken)
        stub.pushConfig = (200, config.replacingOccurrences(of: "/jolt", with: "/jolt/"))
        await backend.registerLastPushToken()

        XCTAssertEqual(stub.relayRegistrations.map(\.url), ["https://relay.example/jolt/v1/devices"])
        XCTAssertTrue(stub.relayUnregistrations.isEmpty, "the same relay, spelled differently, is not a new one")
    }

    /// A route this build doesn't know is an error, and what works stays (C18).
    func testKeepsTheRegistrationWhenTheTransportIsUnknown() async throws {
        let stub = PushStub(pushConfig: (200, relayConfig))
        let backend = try await signedInBackend(stub)
        await backend.registerPushToken(apnsToken)

        stub.pushConfig = (200, #"{"transport":"carrier-pigeon"}"#)
        await backend.registerLastPushToken()

        XCTAssertTrue(stub.relayUnregistrations.isEmpty)
        XCTAssertTrue(stub.forgottenRelayTokens.isEmpty)
        XCTAssertNotNil(registrations.load())
        XCTAssertEqual(backend.pushRegistration.transport, .relay(serverId: serverId))
        XCTAssertEqual(backend.pushRegistration.registeredToken, "rt_issued1")
        XCTAssertNotNil(backend.pushRegistration.problem)
    }

    // MARK: - Back-off (C21)

    func testReadsRetryAfterInSecondsWithAFallback() {
        XCTAssertEqual(RelayClient.retryAfter("120"), 120)
        XCTAssertEqual(RelayClient.retryAfter(" 5 "), 5)
        XCTAssertEqual(RelayClient.retryAfter(nil), RelayClient.defaultRetryAfter)
        XCTAssertEqual(RelayClient.retryAfter("Wed, 21 Oct 2026 07:28:00 GMT"), RelayClient.defaultRetryAfter)
        XCTAssertEqual(RelayClient.retryAfter("-3"), RelayClient.defaultRetryAfter)
    }

    /// Told to wait while replacing a registration: the current one keeps
    /// working, nothing is torn down, and the relay hears nothing more until
    /// the wait is over.
    func testKeepsTheCurrentRegistrationWhileTheRelayAsksToWait() async throws {
        let stub = PushStub(pushConfig: (200, relayConfig))
        let backend = try await signedInBackend(stub)
        await backend.registerPushToken(apnsToken)
        let key = try XCTUnwrap(keys.currentKey(for: serverId))

        stub.rateLimit("/v1/devices", retryAfter: "120")
        await backend.registerPushToken("ffff")

        XCTAssertEqual(stub.relayRegistrations.count, 2)
        XCTAssertEqual(registrations.load()?.relayToken, "rt_issued1")
        XCTAssertEqual(registrations.load()?.apnsToken, apnsToken)
        XCTAssertEqual(keys.currentKey(for: serverId).map(PushEnvelope.keyID(for:)), PushEnvelope.keyID(for: key))
        XCTAssertTrue(stub.relayUnregistrations.isEmpty)
        XCTAssertTrue(stub.forgottenRelayTokens.isEmpty)
        XCTAssertEqual(backend.pushRegistration.registeredToken, "rt_issued1")
        XCTAssertNotNil(backend.pushRegistration.problem)

        clock.addTimeInterval(119)
        await backend.registerLastPushToken()
        XCTAssertEqual(stub.relayRegistrations.count, 2, "not a request before Retry-After has passed")

        stub.rateLimit("/v1/devices", retryAfter: nil)
        clock.addTimeInterval(2)
        await backend.registerLastPushToken()
        XCTAssertEqual(stub.relayRegistrations.count, 3)
        XCTAssertEqual(registrations.load()?.apnsToken, "ffff")
        XCTAssertEqual(stub.relayUnregistrations, ["rt_issued1"])
    }

    /// A 429 on the challenge stops the registration too; going ahead
    /// without attestation would just be the next request the relay refuses.
    func testARateLimitedChallengeStopsTheRegistration() async throws {
        let stub = PushStub(pushConfig: (200, relayConfig))
        stub.rateLimit("/v1/challenge", retryAfter: "30")
        let backend = try await signedInBackend(stub, attestor: FakeAttestor(isSupported: true))

        await backend.registerPushToken(apnsToken)

        XCTAssertEqual(stub.requests("GET", "/v1/challenge").count, 1)
        XCTAssertTrue(stub.relayRegistrations.isEmpty)
        XCTAssertTrue(stub.requests("POST", "/devices/push-token").isEmpty)
        XCTAssertNil(registrations.load())
        XCTAssertNotNil(backend.pushRegistration.problem)
    }

    /// Signing out forgets the registration on the server and the key here at
    /// once. The relay token stays until the relay confirms it is revoked, and
    /// meanwhile a plaintext poke is still refused: the relay can still push
    /// with that token (C9, C21).
    func testARateLimitedUnregisterKeepsTheRelayTokenUntilTheRelayRevokesIt() async throws {
        let stub = PushStub(pushConfig: (200, relayConfig))
        let backend = try await signedInBackend(stub)
        await backend.registerPushToken(apnsToken)

        stub.rateLimit("/v1/devices/unregister", retryAfter: "60")
        await backend.logOut()

        XCTAssertEqual(stub.forgottenRelayTokens, ["rt_issued1"])
        XCTAssertNil(keys.currentKey(for: serverId))
        XCTAssertNil(registrations.load())
        XCTAssertEqual(registrations.pendingUnregistrations().map(\.relayToken), ["rt_issued1"])
        XCTAssertNil(backend.openIncomingPush(plaintextPoke), "the relay can still push with the token")

        stub.rateLimit("/v1/devices/unregister", retryAfter: nil)
        clock.addTimeInterval(30)
        await backend.retryPendingRelayUnregistrations()
        XCTAssertEqual(stub.relayUnregistrations.count, 1, "not before Retry-After has passed")

        clock.addTimeInterval(31)
        await backend.retryPendingRelayUnregistrations()
        XCTAssertEqual(stub.relayUnregistrations, ["rt_issued1", "rt_issued1"])
        XCTAssertTrue(registrations.pendingUnregistrations().isEmpty)
        XCTAssertNotNil(backend.openIncomingPush(plaintextPoke), "revoked at last, so pushes are direct again")
    }

    /// The relay can't be reached when the registration for a server the user
    /// has left is revoked at launch. The token stays pending, plaintext pokes
    /// stay refused, and the next attempt finishes the job.
    func testAnUnreachableRelayKeepsTheRevocationPending() async throws {
        let oldKey = SymmetricKey(size: .bits256)
        keys.save(oldKey, for: "srv_aaaaaaaaaaaaaaaaaaaaaaaaaa")
        defer { keys.remove(for: "srv_aaaaaaaaaaaaaaaaaaaaaaaaaa") }
        registrations.save(RelayRegistration(
            serverBaseURL: URL(string: "https://old.invalid/api/v1")!, relayURL: URL(string: "https://relay.example/")!,
            serverId: "srv_aaaaaaaaaaaaaaaaaaaaaaaaaa", relayToken: "rt_old", apnsToken: apnsToken,
            keyId: PushEnvelope.keyID(for: oldKey)
        ))
        let stub = PushStub(pushConfig: (404, "{}"))
        stub.makeUnreachable("/v1/devices/unregister", true)

        let backend = try await signedInBackend(stub)

        XCTAssertNil(registrations.load())
        XCTAssertNil(keys.currentKey(for: "srv_aaaaaaaaaaaaaaaaaaaaaaaaaa"))
        XCTAssertEqual(registrations.pendingUnregistrations().map(\.relayToken), ["rt_old"])
        XCTAssertNil(backend.openIncomingPush(plaintextPoke))

        stub.makeUnreachable("/v1/devices/unregister", false)
        await backend.registerPushToken(apnsToken)

        XCTAssertEqual(stub.relayUnregistrations, ["rt_old", "rt_old"], "the attempt that failed, then the retry")
        XCTAssertTrue(registrations.pendingUnregistrations().isEmpty)
        XCTAssertNotNil(backend.openIncomingPush(plaintextPoke))
    }

    // MARK: - Receiving

    func testOpensOnlyPushesSealedForTheRegisteredServer() async throws {
        let stub = PushStub(pushConfig: (200, relayConfig))
        let backend = try await signedInBackend(stub)
        await backend.registerPushToken(apnsToken)
        let key = try XCTUnwrap(keys.currentKey(for: serverId))

        let poke = #"{"type":"poke","poke":{"pokeID":"7d6f0c1e-2b3a-4c5d-8e9f-0a1b2c3d4e5f","serverId":"\#(serverId)","#
            + #""sentAt":"\#(Self.timestamp(Date()))","senderHandle":"alice","senderDisplayName":"Alice","stimulus":{"kind":"zap","intensity":30,"repetitions":1}}}"#
        let envelope = try PushEnvelope.seal(Data(poke.utf8), with: key, serverId: serverId, kind: "poke")
        let relayed: [AnyHashable: Any] = ["type": "poke", "srv": serverId, "enc": envelope.jsonObject]

        let opened = try XCTUnwrap(backend.openIncomingPush(relayed))
        XCTAssertEqual(PokePushPayload(userInfo: opened)?.senderHandle, "alice")

        var fromAnotherServer = relayed
        fromAnotherServer["srv"] = "srv_aaaaaaaaaaaaaaaaaaaaaaaaaa"
        XCTAssertNil(backend.openIncomingPush(fromAnotherServer))

        let plaintext: [AnyHashable: Any] = ["type": "poke", "poke": ["pokeID": UUID().uuidString]]
        XCTAssertNil(backend.openIncomingPush(plaintext), "registered through the relay, only sealed pushes count")
    }

    func testRefusesRelayedPushesWhenRegisteredDirectly() async throws {
        let stub = PushStub(pushConfig: (404, "{}"))
        let backend = try await signedInBackend(stub)
        await backend.registerPushToken(apnsToken)

        let relayed: [AnyHashable: Any] = ["type": "poke", "srv": serverId, "enc": ["v": 1]]
        XCTAssertNil(backend.openIncomingPush(relayed))
        let direct: [AnyHashable: Any] = ["type": "poke", "poke": ["pokeID": UUID().uuidString]]
        XCTAssertNotNil(backend.openIncomingPush(direct))
    }

    // MARK: - Helpers

    static func timestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private var plaintextPoke: [AnyHashable: Any] {
        ["type": "poke", "poke": ["pokeID": UUID().uuidString, "senderHandle": "mallory", "senderDisplayName": "Mallory",
                                  "stimulus": ["kind": "zap", "intensity": 100, "repetitions": 1]]]
    }

    private func sealedPoke(with key: SymmetricKey) throws -> [AnyHashable: Any] {
        let poke = #"{"type":"poke","poke":{"pokeID":"\#(UUID().uuidString)","serverId":"\#(serverId)","#
            + #""sentAt":"\#(Self.timestamp(Date()))","senderHandle":"alice","senderDisplayName":"Alice","stimulus":{"kind":"zap","intensity":30,"repetitions":1}}}"#
        let envelope = try PushEnvelope.seal(Data(poke.utf8), with: key, serverId: serverId, kind: "poke")
        return ["type": "poke", "srv": serverId, "enc": envelope.jsonObject]
    }

    private func assertRegisteredDirectly(
        _ stub: PushStub, _ backend: HTTPSocialBackend, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let body = try XCTUnwrap(stub.requests("POST", "/devices/push-token").first?.body, file: file, line: line)
        XCTAssertEqual(body["token"] as? String, apnsToken, file: file, line: line)
        XCTAssertEqual(body["platform"] as? String, "ios", file: file, line: line)
        XCTAssertNil(body["transport"], "an old server must get the body it always got", file: file, line: line)
        XCTAssertTrue(stub.requests(nil, "relay.example").isEmpty, file: file, line: line)
        XCTAssertEqual(backend.pushRegistration.transport, .apns, file: file, line: line)
        XCTAssertEqual(backend.pushRegistration.registeredToken, apnsToken, file: file, line: line)
    }

    private func signedInBackend(
        _ stub: PushStub,
        trustedHosts: TrustedRelayHosts = TrustedRelayHosts(["relay.example"]),
        attestor: AppAttesting? = nil
    ) async throws -> HTTPSocialBackend {
        AuthTokenStore().save("valid-token", for: configuration)
        StubURLProtocol.handler = { stub.handle($0) }
        StubURLProtocol.headers = { stub.headers(for: $0) }

        let session = URLSession(configuration: {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [StubURLProtocol.self]
            return config
        }())
        let backend = HTTPSocialBackend(
            configuration: configuration,
            deviceRepository: FakeDeviceRepository(),
            session: session,
            relay: RelayEnvironment(
                trustedHosts: trustedHosts,
                attestor: attestor ?? FakeAttestor(isSupported: false),
                keys: keys,
                registrations: registrations,
                session: session,
                appId: "cz.peelco.jolt",
                apnsEnvironment: "sandbox",
                backoff: RelayBackoff(defaults: backoffDefaults) { [unowned self] in clock }
            )
        )
        // `restoreSession` runs as a detached task from `init`; wait for it
        // rather than assuming an ordering against it.
        for await user in backend.currentUser where user != nil { break }
        return backend
    }
}

/// App Attest without a Secure Enclave: the first evidence is an
/// attestation, every one after the relay accepted it an assertion.
@MainActor
private final class FakeAttestor: AppAttesting {
    let isSupported: Bool
    private(set) var hashes: [Data] = []
    private var attested = false

    init(isSupported: Bool) {
        self.isSupported = isSupported
    }

    func evidence(for clientDataHash: Data) async throws -> AppAttestEvidence {
        hashes.append(clientDataHash)
        return attested
            ? AppAttestEvidence(keyId: "key-1", assertion: Data("assertion".utf8))
            : AppAttestEvidence(keyId: "key-1", attestationObject: Data("attestation".utf8))
    }

    func accepted(_ evidence: AppAttestEvidence) {
        if evidence.attestationObject != nil { attested = true }
    }

    func reset() {
        attested = false
    }
}

/// A Jolt server and a relay in one `StubURLProtocol` handler, recording
/// every request with its JSON body.
final class PushStub: @unchecked Sendable {
    struct Request {
        var method: String
        var url: String
        var body: [String: Any]?
    }

    private let lock = NSLock()
    private var recorded: [Request] = []
    private var issued = 0
    private var challenges = 0
    private var _pushConfig: (Int, String)
    private var _ackStatus = 204
    private var revoked: Set<String> = []
    private var rateLimits: [String: String] = [:]
    private var unreachable: Set<String> = []

    init(pushConfig: (Int, String)) {
        _pushConfig = pushConfig
    }

    var pushConfig: (Int, String) {
        get { locked { _pushConfig } }
        set { locked { _pushConfig = newValue } }
    }

    var ackStatus: Int {
        get { locked { _ackStatus } }
        set { locked { _ackStatus = newValue } }
    }

    /// From now on the relay answers `429 rate_limited` on paths ending in
    /// `pathSuffix`, with `retryAfter` as its `Retry-After`; nil lifts it.
    func rateLimit(_ pathSuffix: String, retryAfter: String?) {
        locked { rateLimits[pathSuffix] = retryAfter }
    }

    /// While set, requests to the relay on paths ending in `pathSuffix` fail
    /// as if the connection dropped.
    func makeUnreachable(_ pathSuffix: String, _ isUnreachable: Bool) {
        locked { if isUnreachable { unreachable.insert(pathSuffix) } else { unreachable.remove(pathSuffix) } }
    }

    func headers(for request: URLRequest) -> [String: String] {
        guard let retryAfter = rateLimit(for: request) else { return [:] }
        return ["Retry-After": retryAfter]
    }

    private func rateLimit(for request: URLRequest) -> String? {
        guard request.url?.host() == "relay.example", let path = request.url?.path else { return nil }
        return locked { rateLimits.first { path.hasSuffix($0.key) }?.value }
    }

    /// From now on the server answers `410 relay_token_revoked` when this
    /// relay token is posted to it (C6).
    func revoke(_ relayToken: String) {
        locked { _ = revoked.insert(relayToken) }
    }

    /// Registrations with the relay, `POST /v1/devices`.
    var relayRegistrations: [Request] {
        locked { recorded.filter { $0.method == "POST" && $0.url.contains("relay.example/") && $0.url.hasSuffix("/v1/devices") } }
    }

    /// Relay tokens revoked with `POST /v1/devices/unregister`, in order.
    var relayUnregistrations: [String] {
        requests("POST", "/v1/devices/unregister").compactMap { $0.body?["relayToken"] as? String }
    }

    /// Relay tokens the server was told to forget, in order.
    var forgottenRelayTokens: [String] {
        requests("DELETE", "/devices/push-token").compactMap { $0.body?["relayToken"] as? String }
    }

    /// APNs tokens the server was told to forget, in order.
    var forgottenAPNsTokens: [String] {
        requests("DELETE", "/devices/push-token").compactMap { $0.body?["token"] as? String }
    }

    /// Requests whose method matches (any, for nil) and whose URL contains
    /// `fragment`.
    func requests(_ method: String?, _ fragment: String) -> [Request] {
        locked { recorded.filter { (method == nil || $0.method == method) && $0.url.contains(fragment) } }
    }

    func handle(_ request: URLRequest) -> (Int, Data) {
        let method = request.httpMethod ?? "GET"
        let url = request.url?.absoluteString ?? ""
        let path = request.url?.path ?? ""
        let body = try? JSONSerialization.jsonObject(with: request.bodyData) as? [String: Any]
        locked { recorded.append(Request(method: method, url: url, body: body)) }

        if request.url?.host() == "relay.example", locked({ unreachable.contains { path.hasSuffix($0) } }) {
            return (StubURLProtocol.connectionLost, Data())
        }
        if rateLimit(for: request) != nil {
            return (429, Data(#"{"error":"rate_limited"}"#.utf8))
        }
        if request.url?.host() == "relay.example" {
            switch (method, path) {
            case ("GET", _) where path.hasSuffix("/v1/challenge"):
                let challenge = locked { challenges += 1; return Base64URL.encode(Data("challenge-\(challenges)".utf8)) }
                return (200, Data(#"{"challenge":"\#(challenge)","expiresAt":"2026-10-09T12:37:00Z"}"#.utf8))
            case ("POST", _) where path.hasSuffix("/v1/devices"):
                let token = locked { issued += 1; return "rt_issued\(issued)" }
                return (201, Data(#"{"relayToken":"\#(token)"}"#.utf8))
            default:
                return (204, Data())
            }
        }
        if method == "GET", path.hasSuffix("/me") {
            let json = """
            {"id":"\(UUID().uuidString)","handle":"me","displayName":"Me","email":"me@example.com","inviteCode":"JOLT-1234"}
            """
            return (200, Data(json.utf8))
        }
        if method == "GET", path.hasSuffix("/friends") || path.hasSuffix("/pokes") { return (200, Data("[]".utf8)) }
        if method == "GET", path.hasSuffix("/friends/requests") {
            return (200, Data(#"{"incoming":[],"outgoing":[]}"#.utf8))
        }
        if method == "GET", path.hasSuffix("/push/config") {
            let (status, json) = pushConfig
            return (status, Data(json.utf8))
        }
        if method == "POST", path.hasSuffix("/devices/push-token"),
           let relayToken = body?["relayToken"] as? String, locked({ revoked.contains(relayToken) }) {
            return (410, Data(#"{"error":"relay_token_revoked","message":"This relay token has been revoked."}"#.utf8))
        }
        if path.hasSuffix("/ack") {
            return (ackStatus, ackStatus == 404 ? Data(#"{"message":"Not found"}"#.utf8) : Data())
        }
        return (204, Data())
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
