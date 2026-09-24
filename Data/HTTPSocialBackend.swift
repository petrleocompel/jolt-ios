import Foundation

/// Jolt Server user IDs are lowercase (`crypto.randomUUID()` server-side) and
/// compared case-sensitively — but Foundation's `UUID.uuidString` (and its
/// default `Codable` conformance) always emits uppercase. Route paths and
/// request bodies must go through this, not `.uuidString`, or lookups on the
/// server silently miss (see the friend-permission/poke case-mismatch fix).
extension UUID {
    var apiString: String { uuidString.lowercased() }
}

/// Talks to a real Jolt Server. Drop-in replacement for `MockSocialBackend`:
/// same three protocols, same `handleIncomingPoke(_:)` entry point for push
/// delivery, so nothing above this layer changes.
///
/// State is held locally and re-fetched, then republished on the same
/// `AsyncStream`s the mock uses — the contract has no websocket, so the app's
/// view of the friend graph is whatever the last fetch returned.
@MainActor
final class HTTPSocialBackend: AuthRepository, FriendsRepository, PokeRepository {
    private let configuration: ServerConfiguration
    /// Not `private`: `HTTPSocialBackend+PushDiagnostics.swift` is the same
    /// type in another file, and Swift's `private` is file-scoped.
    let client: JoltAPIClient
    private let tokenStore: AuthTokenStore
    let deviceRepository: DeviceRepository

    private var user: User?
    private var inviteCode = ""
    /// Not `private`: `HTTPSocialBackend+Pokes.swift` is the same type in
    /// another file, and Swift's `private` is file-scoped.
    var friendsList: [Friend] = []
    private var incoming: [FriendRequest] = []
    private var outgoing: [FriendRequest] = []
    private var activityLog: [PokeEvent] = []
    /// The last APNs token Apple handed us this launch, signed in or not.
    ///
    /// Kept for the whole process lifetime rather than only until it is first
    /// registered: the server binds a token to exactly one account, so every
    /// change of identity — sign-in, session restore, sign-out — has to say
    /// so, or the binding is whatever it happened to be last time. It used to
    /// be cleared on first use, which meant a second account signing in on
    /// the same launch never registered at all and kept firing pokes at the
    /// first one's wrist.
    private var lastPushToken: String?
    /// Not `private`: `HTTPSocialBackend+PushDiagnostics.swift` fires test
    /// pushes through the same firer, for the same idempotency reason.
    let firer: LocalStimulusFirer

    // `StreamHub`, not a raw `AsyncStream` continuation: Friends, Settings'
    // poke triggers, and the quick-poke picker all subscribe to `friends`
    // independently. A raw `AsyncStream` only supports one live consumer —
    // a second `for await` steals yields from the first, so whichever
    // screen lost the race never saw an update (friend list stuck, a
    // permission toggle not reflecting, "Poke from your Pavlok" showing a
    // stale/empty friend picker). See `StreamHub`'s doc comment for the
    // same bug already hit once with `connectedDevice`.
    private let userHub = StreamHub<User?>()
    private let friendsHub = StreamHub<[Friend]>()
    private let incomingHub = StreamHub<[FriendRequest]>()
    private let outgoingHub = StreamHub<[FriendRequest]>()
    private let activityHub = StreamHub<[PokeEvent]>()

    var myHandle: String { user?.handle ?? "" }
    var myInviteCode: String { inviteCode }

    init(
        configuration: ServerConfiguration,
        deviceRepository: DeviceRepository,
        tokenStore: AuthTokenStore = AuthTokenStore(),
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.deviceRepository = deviceRepository
        self.tokenStore = tokenStore
        self.firer = LocalStimulusFirer(deviceRepository: deviceRepository)
        self.client = JoltAPIClient(
            configuration: configuration,
            token: tokenStore.token(for: configuration),
            session: session
        )
        // A token from a previous launch means we're probably still signed
        // in; confirm with the server rather than assuming either way. Run
        // once here rather than on first `currentUser` subscription — with
        // `StreamHub`, every subscriber gets its own fresh stream, so tying
        // it to subscription would re-run it once per subscriber.
        Task { await self.restoreSession() }
    }

    var currentUser: AsyncStream<User?> { userHub.stream() }
    var friends: AsyncStream<[Friend]> { friendsHub.stream() }
    var incomingRequests: AsyncStream<[FriendRequest]> { incomingHub.stream() }
    var outgoingRequests: AsyncStream<[FriendRequest]> { outgoingHub.stream() }
    var activity: AsyncStream<[PokeEvent]> { activityHub.stream() }

    // MARK: - Requests
    //
    // Every authenticated call goes through these two rather than `client`
    // directly, so a token rejected mid-session (revoked, or from a server
    // we no longer point at) logs out immediately instead of only being
    // caught at the next launch's `restoreSession`. `restoreSession` itself
    // calls `client.send` directly — it already handles `.unauthorized`
    // explicitly and would otherwise call `logOut()` twice.
    //
    // Not `private`: `HTTPSocialBackend+PushDiagnostics.swift` is the same
    // type in another file, and Swift's `private` is file-scoped.

    func send<Response: Decodable>(
        _ method: String, _ path: String,
        body: (some Encodable)? = Optional<Never>.none,
        query: [String: String] = [:]
    ) async throws -> Response {
        do {
            return try await client.send(method, path, body: body, query: query)
        } catch JoltAPIClient.APIError.unauthorized {
            await logOut()
            throw JoltAPIClient.APIError.unauthorized
        }
    }

    func sendIgnoringResponse(
        _ method: String, _ path: String,
        body: (some Encodable)? = Optional<Never>.none
    ) async throws {
        do {
            try await client.sendIgnoringResponse(method, path, body: body)
        } catch JoltAPIClient.APIError.unauthorized {
            await logOut()
            throw JoltAPIClient.APIError.unauthorized
        }
    }

    // MARK: - Auth

    private struct AuthResponse: Decodable {
        let token: String
        let user: MeResponse
    }

    private struct MeResponse: Decodable {
        let id: UUID
        let handle: String
        let displayName: String
        let email: String
        let inviteCode: String

        var asUser: User { User(id: id, handle: handle, displayName: displayName, email: email) }
    }

    private struct SignUpBody: Encodable {
        let email: String
        let password: String
        let handle: String
        let displayName: String
    }

    private struct LogInBody: Encodable {
        let email: String
        let password: String
    }

    func signUp(email: String, password: String, handle: String, displayName: String) async throws {
        let response: AuthResponse = try await send(
            "POST", "auth/signup",
            body: SignUpBody(
                email: email.trimmingCharacters(in: .whitespaces),
                password: password,
                handle: handle.trimmingCharacters(in: .whitespaces).lowercased(),
                displayName: displayName
            )
        )
        try await adopt(response)
    }

    func logIn(email: String, password: String) async throws {
        let response: AuthResponse = try await send(
            "POST", "auth/login",
            body: LogInBody(email: email.trimmingCharacters(in: .whitespaces), password: password)
        )
        try await adopt(response)
    }

    private func adopt(_ response: AuthResponse) async throws {
        tokenStore.save(response.token, for: configuration)
        await client.setToken(response.token)
        user = response.user.asUser
        inviteCode = response.user.inviteCode
        userHub.yield(user)
        await registerLastPushToken()
        await refreshAll()
    }

    func logOut() async {
        // Best effort: a failed logout call must not leave the app stuck in a
        // signed-in state it can't get out of, so local state is cleared
        // either way.
        //
        // Both calls go through `client` rather than the `sendIgnoringResponse`
        // wrapper above, which logs out on 401 — from in here that recurses.
        if let lastPushToken, user != nil {
            // Unbind this phone before the session goes: the registration
            // outlives it otherwise, and the account keeps this device as a
            // poke target until something re-registers the token. A friend
            // poking *them* would fire on this wrist.
            try? await client.sendIgnoringResponse(
                "DELETE", "devices/push-token",
                body: ForgetPushTokenBody(token: lastPushToken)
            )
        }
        try? await client.sendIgnoringResponse("POST", "auth/logout")
        tokenStore.clear(for: configuration)
        await client.setToken(nil)
        user = nil
        inviteCode = ""
        friendsList = []
        incoming = []
        outgoing = []
        activityLog = []
        userHub.yield(nil)
        friendsHub.yield([])
        incomingHub.yield([])
        outgoingHub.yield([])
        activityHub.yield([])
    }

    private func restoreSession() async {
        guard tokenStore.token(for: configuration) != nil else { return }
        do {
            let profile: MeResponse = try await client.send("GET", "me")
            user = profile.asUser
            inviteCode = profile.inviteCode
            userHub.yield(user)
            // Apple hands the token over within milliseconds of launch, well
            // before this round-trip finishes, so on a restored session it is
            // almost always still waiting here. Registering only on an
            // explicit sign-in left it unsent for the whole run.
            await registerLastPushToken()
            await refreshAll()
        } catch JoltAPIClient.APIError.unauthorized {
            // Token was rejected — expired, revoked, or from a server we no
            // longer point at. Drop it rather than retrying forever.
            await logOut()
        } catch {
            // Offline or server down: keep the token and stay signed out for
            // now rather than destroying a session over a flaky network.
        }
    }

    struct PushTokenBody: Encodable {
        let token: String
        let platform = "ios"
    }

    struct ForgetPushTokenBody: Encodable {
        let token: String
    }

    func registerPushToken(_ token: String) async {
        lastPushToken = token
        // Nothing to attach it to yet; whoever signs in (or the session
        // restore) sends it. Remembered either way — see `lastPushToken`.
        guard user != nil else { return }
        try? await sendIgnoringResponse("POST", "devices/push-token", body: PushTokenBody(token: token))
    }

    /// Re-asserts this phone's registration for whoever is signed in now.
    /// Idempotent server-side (the token is the conflict target), so calling
    /// it on every identity change costs one request and buys the guarantee
    /// that the binding matches the session.
    ///
    /// Not `private`: a poke arriving for the wrong account is the clearest
    /// evidence the registration is stale, and that is handled in
    /// `HTTPSocialBackend+Pokes.swift`.
    func registerLastPushToken() async {
        guard let lastPushToken else { return }
        await registerPushToken(lastPushToken)
    }

    // MARK: - Friends

    private struct RequestsResponse: Decodable {
        let incoming: [FriendRequest]
        let outgoing: [FriendRequest]
    }

    private struct SendRequestBody: Encodable {
        var handle: String?
        var inviteCode: String?
    }

    func sendRequest(handle: String) async throws {
        let _: FriendRequest = try await send(
            "POST", "friends/requests",
            body: SendRequestBody(handle: handle.trimmingCharacters(in: .whitespaces).lowercased())
        )
        await refreshRequests()
    }

    func sendRequest(inviteCode: String) async throws {
        let _: FriendRequest = try await send(
            "POST", "friends/requests",
            body: SendRequestBody(inviteCode: inviteCode.trimmingCharacters(in: .whitespaces))
        )
        await refreshRequests()
    }

    func acceptRequest(_ id: FriendRequest.ID) async throws {
        let _: Friend = try await send("POST", "friends/requests/\(id.apiString)/accept")
        await refreshFriends()
        await refreshRequests()
    }

    func rejectRequest(_ id: FriendRequest.ID) async throws {
        try await sendIgnoringResponse("POST", "friends/requests/\(id.apiString)/reject")
        await refreshRequests()
    }

    func removeFriend(_ id: Friend.ID) async throws {
        try await sendIgnoringResponse("DELETE", "friends/\(id.apiString)")
        await refreshFriends()
    }

    func updatePermission(for friendID: Friend.ID, kind: StimulusKind, permission: StimulusPermission) async throws {
        let _: StimulusPermission = try await send(
            "PUT", "friends/\(friendID.apiString)/permissions/\(kind.rawValue)",
            body: permission
        )
        await refreshFriends()
    }
}

/// Re-fetching. The contract has no websocket, so the app's view of the
/// friend graph is whatever the last fetch returned; every mutation refreshes
/// what it could have changed.
extension HTTPSocialBackend {
    private func refreshAll() async {
        await refreshFriends()
        await refreshRequests()
        await refreshActivity()
    }

    // Not `private`: `FriendsRepository.refreshFriends()` lets callers that
    // subscribed after the launch-time fetch already failed (offline, server
    // unreachable) retry it explicitly, since `friends` otherwise never
    // yields again on its own.
    func refreshFriends() async {
        guard let list: [Friend] = try? await send("GET", "friends") else { return }
        friendsList = list
        friendsHub.yield(list)
    }

    private func refreshRequests() async {
        guard let response: RequestsResponse = try? await send("GET", "friends/requests") else { return }
        incoming = response.incoming
        outgoing = response.outgoing
        incomingHub.yield(incoming)
        outgoingHub.yield(outgoing)
    }

    // Not `private`: `HTTPSocialBackend+Pokes.swift` sends and acks pokes,
    // and every one of them changes the activity log.
    func refreshActivity() async {
        guard let events: [PokeEvent] = try? await send("GET", "pokes") else { return }
        activityLog = events
        activityHub.yield(events)
    }
}
