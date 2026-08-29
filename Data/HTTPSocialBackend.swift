import Foundation

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
    private let client: JoltAPIClient
    private let tokenStore: AuthTokenStore
    private let deviceRepository: DeviceRepository

    private var user: User?
    private var inviteCode = ""
    private var friendsList: [Friend] = []
    private var incoming: [FriendRequest] = []
    private var outgoing: [FriendRequest] = []
    private var activityLog: [PokeEvent] = []
    /// Held until the account is known — a token arriving before
    /// `registerPushToken` has an account to attach it to would 401.
    private var pendingPushToken: String?

    private var userContinuation: AsyncStream<User?>.Continuation?
    private var friendsContinuation: AsyncStream<[Friend]>.Continuation?
    private var incomingContinuation: AsyncStream<[FriendRequest]>.Continuation?
    private var outgoingContinuation: AsyncStream<[FriendRequest]>.Continuation?
    private var activityContinuation: AsyncStream<[PokeEvent]>.Continuation?

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
        self.client = JoltAPIClient(
            configuration: configuration,
            token: tokenStore.token(for: configuration),
            session: session
        )
    }

    private(set) lazy var currentUser: AsyncStream<User?> = AsyncStream { continuation in
        self.userContinuation = continuation
        continuation.yield(self.user)
        // A token from a previous launch means we're probably still signed
        // in; confirm with the server rather than assuming either way.
        Task { await self.restoreSession() }
    }

    private(set) lazy var friends: AsyncStream<[Friend]> = AsyncStream { continuation in
        self.friendsContinuation = continuation
        continuation.yield(self.friendsList)
    }

    private(set) lazy var incomingRequests: AsyncStream<[FriendRequest]> = AsyncStream { continuation in
        self.incomingContinuation = continuation
        continuation.yield(self.incoming)
    }

    private(set) lazy var outgoingRequests: AsyncStream<[FriendRequest]> = AsyncStream { continuation in
        self.outgoingContinuation = continuation
        continuation.yield(self.outgoing)
    }

    private(set) lazy var activity: AsyncStream<[PokeEvent]> = AsyncStream { continuation in
        self.activityContinuation = continuation
        continuation.yield(self.activityLog)
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
        let response: AuthResponse = try await client.send(
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
        let response: AuthResponse = try await client.send(
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
        userContinuation?.yield(user)
        if let pendingPushToken {
            self.pendingPushToken = nil
            await registerPushToken(pendingPushToken)
        }
        await refreshAll()
    }

    func logOut() async {
        // Best effort: a failed logout call must not leave the app stuck in a
        // signed-in state it can't get out of, so local state is cleared
        // either way.
        try? await client.sendIgnoringResponse("POST", "auth/logout")
        tokenStore.clear(for: configuration)
        await client.setToken(nil)
        user = nil
        inviteCode = ""
        friendsList = []
        incoming = []
        outgoing = []
        activityLog = []
        userContinuation?.yield(nil)
        friendsContinuation?.yield([])
        incomingContinuation?.yield([])
        outgoingContinuation?.yield([])
        activityContinuation?.yield([])
    }

    private func restoreSession() async {
        guard tokenStore.token(for: configuration) != nil else { return }
        do {
            let profile: MeResponse = try await client.send("GET", "me")
            user = profile.asUser
            inviteCode = profile.inviteCode
            userContinuation?.yield(user)
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

    func registerPushToken(_ token: String) async {
        guard user != nil else {
            pendingPushToken = token
            return
        }
        try? await client.sendIgnoringResponse("POST", "devices/push-token", body: PushTokenBody(token: token))
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
        let _: FriendRequest = try await client.send(
            "POST", "friends/requests",
            body: SendRequestBody(handle: handle.trimmingCharacters(in: .whitespaces).lowercased())
        )
        await refreshRequests()
    }

    func sendRequest(inviteCode: String) async throws {
        let _: FriendRequest = try await client.send(
            "POST", "friends/requests",
            body: SendRequestBody(inviteCode: inviteCode.trimmingCharacters(in: .whitespaces))
        )
        await refreshRequests()
    }

    func acceptRequest(_ id: FriendRequest.ID) async throws {
        let _: Friend = try await client.send("POST", "friends/requests/\(id.uuidString)/accept")
        await refreshFriends()
        await refreshRequests()
    }

    func rejectRequest(_ id: FriendRequest.ID) async throws {
        try await client.sendIgnoringResponse("POST", "friends/requests/\(id.uuidString)/reject")
        await refreshRequests()
    }

    func removeFriend(_ id: Friend.ID) async throws {
        try await client.sendIgnoringResponse("DELETE", "friends/\(id.uuidString)")
        await refreshFriends()
    }

    func updatePermission(for friendID: Friend.ID, kind: StimulusKind, permission: StimulusPermission) async throws {
        let _: StimulusPermission = try await client.send(
            "PUT", "friends/\(friendID.uuidString)/permissions/\(kind.rawValue)",
            body: permission
        )
        await refreshFriends()
    }

    // MARK: - Pokes

    private struct SendPokeBody: Encodable {
        let friendId: UUID
        let stimulus: StimulusConfig
    }

    private struct AckBody: Encodable {
        let status: PokeDeliveryStatus
    }

    func sendPoke(to friendID: Friend.ID, stimulus: StimulusConfig) async throws {
        let _: PokeEvent = try await client.send(
            "POST", "pokes",
            body: SendPokeBody(friendId: friendID, stimulus: stimulus)
        )
        await refreshActivity()
    }

    @discardableResult
    func handleIncomingPoke(_ payload: PokePushPayload) async -> PokeDeliveryStatus {
        let status = await deliver(payload)
        // Tell the server what actually happened. Idempotent server-side, so
        // an alert push and a silent push for the same poke are both safe to
        // ack.
        try? await client.sendIgnoringResponse(
            "POST", "pokes/\(payload.pokeID.uuidString)/ack",
            body: AckBody(status: status)
        )
        await refreshActivity()
        return status
    }

    /// Fires the stimulus locally, applying the same do-not-disturb rule the
    /// mock uses. The server has already checked permissions; this is the
    /// recipient-side half.
    private func deliver(_ payload: PokePushPayload) async -> PokeDeliveryStatus {
        if UserDefaults.standard.bool(forKey: PokeSettings.doNotDisturbKey) {
            return .muted
        }
        do {
            try await deviceRepository.fire(payload.stimulus)
            return .fired
        } catch {
            return .deviceNotConnected
        }
    }

    func simulateIncomingPoke(from friendID: Friend.ID, stimulus: StimulusConfig) async {
        guard let friend = friendsList.first(where: { $0.id == friendID }) else { return }
        await handleIncomingPoke(PokePushPayload(
            pokeID: UUID(),
            senderHandle: friend.handle,
            senderDisplayName: friend.displayName,
            stimulus: stimulus
        ))
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

    private func refreshFriends() async {
        guard let list: [Friend] = try? await client.send("GET", "friends") else { return }
        friendsList = list
        friendsContinuation?.yield(list)
    }

    private func refreshRequests() async {
        guard let response: RequestsResponse = try? await client.send("GET", "friends/requests") else { return }
        incoming = response.incoming
        outgoing = response.outgoing
        incomingContinuation?.yield(incoming)
        outgoingContinuation?.yield(outgoing)
    }

    private func refreshActivity() async {
        guard let events: [PokeEvent] = try? await client.send("GET", "pokes") else { return }
        activityLog = events
        activityContinuation?.yield(events)
    }
}
