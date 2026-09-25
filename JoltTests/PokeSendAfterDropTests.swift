import XCTest
@testable import Jolt

/// Locking the phone right after "Tap to poke" can drop the connection after
/// the request reached the server but before the answer came back. The poke
/// was sent; the app only knows the connection died. These pin down that it
/// asks the activity feed instead of guessing — and never calls a poke that
/// landed "not sent".
@MainActor
final class PokeSendAfterDropTests: XCTestCase {
    private let configuration = ServerConfiguration(baseURL: URL(string: "https://unit-test.invalid/api/v1")!)
    private let friendID = UUID()
    private let stimulus = StimulusConfig(kind: .zap, intensity: 30, repetitions: 1)

    override func tearDown() {
        AuthTokenStore().clear(for: configuration)
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    func testAPokeTheServerRecordedCountsAsSentEvenThoughTheAnswerWasLost() async throws {
        let pokeID = UUID()
        let backend = try await backend(postPokes: StubURLProtocol.connectionLost, feed: .contains(pokeID))

        // No throw: it landed, and saying otherwise invites a second one.
        try await backend.sendPoke(to: friendID, stimulus: stimulus, pokeID: pokeID)
    }

    func testAPokeTheServerNeverRecordedIsNotSent() async throws {
        let backend = try await backend(postPokes: StubURLProtocol.connectionLost, feed: .empty)

        await assertThrows(PokeSendError.notSent) {
            try await backend.sendPoke(to: self.friendID, stimulus: self.stimulus, pokeID: UUID())
        }
    }

    /// Still offline when it tries to check: it genuinely can't know, and must
    /// say so rather than pick an answer.
    func testUnconfirmedWhenTheFeedCannotBeCheckedEither() async throws {
        let backend = try await backend(postPokes: StubURLProtocol.connectionLost, feed: .unreachable)

        await assertThrows(PokeSendError.unconfirmed) {
            try await backend.sendPoke(to: self.friendID, stimulus: self.stimulus, pokeID: UUID())
        }
    }

    /// The id is what the server dedupes a retry on, so it has to be on the
    /// wire — in the lowercase form the server stores.
    func testSendsThePokeIDWithTheRequest() async throws {
        let pokeID = UUID()
        let bodies = RequestRecorder()
        let backend = try await backend(postPokes: 201, feed: .empty, recordPokeBodies: bodies)

        try await backend.sendPoke(to: friendID, stimulus: stimulus, pokeID: pokeID)

        XCTAssertTrue(bodies.paths.contains { $0.contains("\"pokeId\":\"\(pokeID.apiString)\"") })
    }

    // MARK: - Helpers

    private enum Feed {
        case empty, unreachable
        case contains(UUID)
    }

    private func backend(
        postPokes status: Int,
        feed: Feed,
        recordPokeBodies: RequestRecorder? = nil
    ) async throws -> HTTPSocialBackend {
        AuthTokenStore().save("valid-token", for: configuration)
        let pokeJSON = { (id: UUID) in
            """
            {"id":"\(id.apiString)","direction":"sent","friendHandle":"alice","friendDisplayName":"Alice",\
            "stimulus":{"kind":"zap","intensity":30,"repetitions":1},"status":"pending",\
            "createdAt":"2026-09-25T10:00:00Z","ackedAt":null}
            """
        }
        // Signing in is the only thing allowed through before the test proper.
        let signedIn = SignedInFlag()

        StubURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            let method = request.httpMethod ?? "GET"
            if path.hasSuffix("/me") {
                return (200, Data(#"{"id":"\#(UUID().uuidString)","handle":"me","displayName":"Me","email":"me@example.com","inviteCode":"JOLT-1"}"#.utf8))
            }
            if path.hasSuffix("/friends") { return (200, Data("[]".utf8)) }
            if path.hasSuffix("/friends/requests") { return (200, Data(#"{"incoming":[],"outgoing":[]}"#.utf8)) }
            if method == "POST", path.hasSuffix("/pokes") {
                recordPokeBodies?.record(String(decoding: request.bodyData, as: UTF8.self))
                return (status, status == 201 ? Data(pokeJSON(UUID()).utf8) : Data())
            }
            if method == "GET", path.hasSuffix("/pokes") {
                // The launch-time refresh must succeed so the backend signs in.
                guard signedIn.value else { return (200, Data("[]".utf8)) }
                switch feed {
                case .empty: return (200, Data("[]".utf8))
                case .unreachable: return (StubURLProtocol.connectionLost, Data())
                case .contains(let id): return (200, Data("[\(pokeJSON(id))]".utf8))
                }
            }
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
        for await user in backend.currentUser where user != nil { break }
        // Let `restoreSession`'s follow-up refreshes drain before switching
        // the feed over to what the test wants it to say.
        try await Task.sleep(for: .milliseconds(200))
        signedIn.value = true
        return backend
    }

    private func assertThrows(
        _ expected: PokeSendError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () async throws -> Void
    ) async {
        do {
            try await body()
            XCTFail("expected \(expected), got success", file: file, line: line)
        } catch let error as PokeSendError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("expected \(expected), got \(error)", file: file, line: line)
        }
    }
}

private final class SignedInFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var value: Bool {
        get { lock.lock(); defer { lock.unlock() }; return flag }
        set { lock.lock(); flag = newValue; lock.unlock() }
    }
}

private extension URLRequest {
    /// URLSession hands a stubbed protocol the body as a stream, not `httpBody`.
    var bodyData: Data {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
