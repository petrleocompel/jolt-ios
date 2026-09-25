import XCTest
@testable import Jolt

@MainActor
final class HTTPSocialBackendTests: XCTestCase {
    private let configuration = ServerConfiguration(baseURL: URL(string: "https://unit-test.invalid/api/v1")!)

    override func tearDown() {
        AuthTokenStore().clear(for: configuration)
        super.tearDown()
    }

    /// A 401 from any authenticated call — not just the launch-time
    /// `restoreSession` check — must sign the user out immediately, so a
    /// token revoked mid-session doesn't leave the UI on stale authenticated
    /// state until the next app launch.
    func testUnauthorizedResponseMidSessionSignsOut() async throws {
        // A valid-looking token, so `restoreSession` (fired on init) signs
        // in via `GET /me` and its `refreshAll()` follow-ups all succeed —
        // isolating the 401 to the one deliberate call below.
        AuthTokenStore().save("valid-token", for: configuration)

        StubURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            let isGET = request.httpMethod == "GET"
            if isGET, path.hasSuffix("/me") {
                let json = """
                {"id":"\(UUID().uuidString)","handle":"me","displayName":"Me","email":"me@example.com","inviteCode":"JOLT-1234"}
                """
                return (200, Data(json.utf8))
            }
            if isGET, path.hasSuffix("/friends") {
                return (200, Data("[]".utf8))
            }
            if isGET, path.hasSuffix("/friends/requests") {
                return (200, Data("{\"incoming\":[],\"outgoing\":[]}".utf8))
            }
            if isGET, path.hasSuffix("/pokes") {
                return (200, Data("[]".utf8))
            }
            // Everything else — specifically the deliberate
            // `POST /friends/requests` below — is a rejected token.
            return (401, Data("{\"message\":\"Token expired\"}".utf8))
        }
        defer { StubURLProtocol.handler = nil }

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

        // Wait for `restoreSession` (fired in `init`) to actually sign in,
        // rather than assuming ordering against that background task.
        for await user in backend.currentUser where user != nil {
            break
        }

        // Any authenticated call 401ing must trigger a sign-out.
        try? await backend.sendRequest(handle: "someone")

        var signedOutIterator = backend.currentUser.makeAsyncIterator()
        let signedOutUser = await signedOutIterator.next() ?? nil
        XCTAssertNil(signedOutUser)
    }
}

/// Stubs every request `HTTPSocialBackend`'s `URLSession` makes, so tests can
/// simulate specific server responses (here, a 401) without a real server.
///
/// A handler returning `StubURLProtocol.connectionLost` as the status fails
/// the request the way a locked phone does: no response at all.
final class StubURLProtocol: URLProtocol {
    static let connectionLost = -1

    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Int, Data))?

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let (status, data) = handler(request)
        if status == Self.connectionLost {
            client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
            return
        }
        guard let response = HTTPURLResponse(
            url: url, statusCode: status, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
