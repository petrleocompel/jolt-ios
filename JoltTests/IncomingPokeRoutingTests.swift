import XCTest
@testable import Jolt

/// A poke fires a shock. Which wrist it fires on is decided entirely by which
/// account the server has this device registered to — and that binding can go
/// stale (signed in as someone else, signed out, token never re-registered).
/// These cover the client's half of not shocking the wrong person.
@MainActor
final class IncomingPokeRoutingTests: XCTestCase {
    private let configuration = ServerConfiguration(baseURL: URL(string: "https://unit-test.invalid/api/v1")!)

    override func tearDown() {
        AuthTokenStore().clear(for: configuration)
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    func testFiresAPokeAddressedToTheSignedInAccount() async throws {
        let recorder = RequestRecorder()
        let backend = try await signedInBackend(as: "me", recorder: recorder)

        let status = await backend.handleIncomingPoke(payload(recipientHandle: "me"))

        XCTAssertEqual(status, .fired)
        XCTAssertTrue(recorder.paths.contains { $0.contains("/ack") }, "a poke that fires must be acked")
    }

    /// The payload predates `recipientHandle`, so there is nothing to compare.
    /// "Can't tell" must never be read as "not mine" — that would silently
    /// stop every poke against an older server.
    func testFiresWhenThePayloadNamesNoRecipient() async throws {
        let backend = try await signedInBackend(as: "me", recorder: RequestRecorder())

        let status = await backend.handleIncomingPoke(payload(recipientHandle: nil))

        XCTAssertEqual(status, .fired)
    }

    func testDropsAPokeAddressedToSomebodyElse() async throws {
        let recorder = RequestRecorder()
        let backend = try await signedInBackend(as: "me", recorder: recorder)

        let status = await backend.handleIncomingPoke(payload(recipientHandle: "someone-else"))

        XCTAssertEqual(status, .notAllowed, "a poke for another account must not reach the wearable")
        XCTAssertFalse(
            recorder.paths.contains { $0.contains("/ack") },
            "there is nothing to ack: the server only accepts an ack from the poke's recipient"
        )
    }

    // MARK: - Helpers

    private func payload(recipientHandle: String?) -> PokePushPayload {
        PokePushPayload(
            pokeID: UUID(),
            senderHandle: "alice",
            senderDisplayName: "Alice",
            recipientHandle: recipientHandle,
            stimulus: StimulusConfig(kind: .zap, intensity: 30, repetitions: 1)
        )
    }

    private func signedInBackend(as handle: String, recorder: RequestRecorder) async throws -> HTTPSocialBackend {
        AuthTokenStore().save("valid-token", for: configuration)

        StubURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            recorder.record(path)
            if path.hasSuffix("/me") {
                let json = """
                {"id":"\(UUID().uuidString)","handle":"\(handle)","displayName":"Me",\
                "email":"me@example.com","inviteCode":"JOLT-1234"}
                """
                return (200, Data(json.utf8))
            }
            if path.hasSuffix("/friends") { return (200, Data("[]".utf8)) }
            if path.hasSuffix("/friends/requests") { return (200, Data("{\"incoming\":[],\"outgoing\":[]}".utf8)) }
            if path.hasSuffix("/pokes") { return (200, Data("[]".utf8)) }
            return (204, Data())
        }

        let session = URLSession(configuration: {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [StubURLProtocol.self]
            return config
        }())

        let backend = HTTPSocialBackend(
            configuration: configuration,
            deviceRepository: FakeDeviceRepository(),
            session: session
        )
        // `restoreSession` runs as a detached task from `init`; wait for it
        // rather than assuming an ordering against it.
        for await user in backend.currentUser where user != nil { break }
        return backend
    }
}

/// Collects the paths the backend asked for, so a test can assert on what was
/// *not* sent as easily as on what was.
final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []

    var paths: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func record(_ path: String) {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(path)
    }
}
