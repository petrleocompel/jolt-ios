import Foundation

/// Stand-in for the real server (see `docs/openapi.yaml`) — implements all
/// three social-feature protocols against in-memory state so the UI can be
/// built and demoed before the backend exists. `handleIncomingPoke(_:)` is
/// the one method real push delivery will also call once the server ships,
/// so swapping this for an `HTTPSocialBackend` later shouldn't need UI
/// changes.
@MainActor
final class MockSocialBackend: AuthRepository, FriendsRepository, PokeRepository {
    enum MockBackendError: LocalizedError {
        case invalidCredentials
        case handleNotFound
        case alreadyFriends
        case notAllowed

        var errorDescription: String? {
            switch self {
            case .invalidCredentials: return "Invalid email or password."
            case .handleNotFound: return "No user with that handle or invite code."
            case .alreadyFriends: return "You're already friends."
            case .notAllowed: return "They haven't allowed that stimulus, or the intensity is too high."
            }
        }
    }

    /// Not `private`: `MockSocialBackend+PushDiagnostics.swift` is the same
    /// type in another file, and Swift's `private` is file-scoped.
    let deviceRepository: DeviceRepository

    private var user: User?
    private var friendsList: [Friend] = []
    private var incoming: [FriendRequest] = []
    private var outgoing: [FriendRequest] = []
    private var activityLog: [PokeEvent] = []
    private var didSeed = false

    private var userContinuation: AsyncStream<User?>.Continuation?
    private var friendsContinuation: AsyncStream<[Friend]>.Continuation?
    private var incomingContinuation: AsyncStream<[FriendRequest]>.Continuation?
    private var outgoingContinuation: AsyncStream<[FriendRequest]>.Continuation?
    private var activityContinuation: AsyncStream<[PokeEvent]>.Continuation?

    /// Static per app-install for the mock; a real backend issues one per
    /// account at signup.
    let myInviteCode = "JOLT-DEMO-4821"
    var myHandle: String { user?.handle ?? "" }

    init(deviceRepository: DeviceRepository) {
        self.deviceRepository = deviceRepository
    }

    private(set) lazy var currentUser: AsyncStream<User?> = AsyncStream { continuation in
        self.userContinuation = continuation
        continuation.yield(self.user)
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

    func signUp(email: String, password: String, handle: String, displayName: String) async throws {
        try await Task.sleep(for: .milliseconds(400))
        let normalizedHandle = handle.trimmingCharacters(in: .whitespaces).lowercased()
        let newUser = User(id: UUID(), handle: normalizedHandle, displayName: displayName, email: email)
        user = newUser
        seedDemoDataIfNeeded()
        userContinuation?.yield(newUser)
    }

    func logIn(email: String, password: String) async throws {
        try await Task.sleep(for: .milliseconds(400))
        guard !email.isEmpty, !password.isEmpty else { throw MockBackendError.invalidCredentials }
        let newUser = User(id: UUID(), handle: "you", displayName: "You", email: email)
        user = newUser
        seedDemoDataIfNeeded()
        userContinuation?.yield(newUser)
    }

    func logOut() async {
        user = nil
        userContinuation?.yield(nil)
    }

    func registerPushToken(_ token: String) async {
        #if DEBUG
        print("[MockSocialBackend] Would register push token: \(token)")
        #endif
    }

    // MARK: - Friends

    func sendRequest(handle: String) async throws {
        try await Task.sleep(for: .milliseconds(300))
        let normalized = handle.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: "@", with: "")
        guard !normalized.isEmpty else { throw MockBackendError.handleNotFound }
        guard !friendsList.contains(where: { $0.handle == normalized }) else { throw MockBackendError.alreadyFriends }
        let request = FriendRequest(
            id: UUID(), handle: normalized, displayName: normalized.capitalized, direction: .outgoing, createdAt: .now
        )
        outgoing.append(request)
        outgoingContinuation?.yield(outgoing)
    }

    func sendRequest(inviteCode: String) async throws {
        try await Task.sleep(for: .milliseconds(300))
        let trimmed = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MockBackendError.handleNotFound }
        let handle = "guest-\(trimmed.suffix(4).lowercased())"
        outgoing.append(FriendRequest(id: UUID(), handle: handle, displayName: handle.capitalized, direction: .outgoing, createdAt: .now))
        outgoingContinuation?.yield(outgoing)
    }

    func acceptRequest(_ id: FriendRequest.ID) async throws {
        try await Task.sleep(for: .milliseconds(200))
        guard let index = incoming.firstIndex(where: { $0.id == id }) else { return }
        let request = incoming.remove(at: index)
        let friend = Friend(
            id: request.id,
            handle: request.handle,
            displayName: request.displayName,
            permissionsGrantedToMe: FriendPermissionSet(zap: .allowed(), vibe: .allowed(), beep: .allowed()),
            permissionsIGranted: .none
        )
        friendsList.append(friend)
        incomingContinuation?.yield(incoming)
        friendsContinuation?.yield(friendsList)
    }

    func rejectRequest(_ id: FriendRequest.ID) async throws {
        try await Task.sleep(for: .milliseconds(200))
        incoming.removeAll { $0.id == id }
        incomingContinuation?.yield(incoming)
    }

    func removeFriend(_ id: Friend.ID) async throws {
        try await Task.sleep(for: .milliseconds(200))
        friendsList.removeAll { $0.id == id }
        friendsContinuation?.yield(friendsList)
    }

    func updatePermission(for friendID: Friend.ID, kind: StimulusKind, permission: StimulusPermission) async throws {
        try await Task.sleep(for: .milliseconds(200))
        guard let index = friendsList.firstIndex(where: { $0.id == friendID }) else { return }
        friendsList[index].permissionsIGranted[kind] = permission
        friendsContinuation?.yield(friendsList)
    }

    // MARK: - Pokes

    func sendPoke(to friendID: Friend.ID, stimulus: StimulusConfig) async throws {
        guard let friend = friendsList.first(where: { $0.id == friendID }) else { return }
        let permission = friend.permissionsGrantedToMe[stimulus.kind]
        let isAllowed = permission.isAllowed && stimulus.intensity <= permission.maxIntensity
        try await Task.sleep(for: .milliseconds(300))
        let event = PokeEvent(
            id: UUID(),
            direction: .sent,
            friendHandle: friend.handle,
            friendDisplayName: friend.displayName,
            stimulus: stimulus,
            status: isAllowed ? .fired : .notAllowed,
            createdAt: .now
        )
        activityLog.insert(event, at: 0)
        activityContinuation?.yield(activityLog)
        guard isAllowed else { throw MockBackendError.notAllowed }
    }

    @discardableResult
    func handleIncomingPoke(_ payload: PokePushPayload) async -> PokeDeliveryStatus {
        // Idempotency check BEFORE firing: a poke can arrive via both a
        // background silent push and a subsequent notification tap — must
        // never fire the same poke twice.
        if let existing = activityLog.first(where: { $0.id == payload.pokeID }) {
            return existing.status
        }
        var status: PokeDeliveryStatus
        if UserDefaults.standard.bool(forKey: PokeSettings.doNotDisturbKey) {
            status = .muted
        } else {
            do {
                try await deviceRepository.fire(payload.stimulus)
                status = .fired
            } catch {
                status = .deviceNotConnected
            }
        }
        let event = PokeEvent(
            id: payload.pokeID,
            direction: .received,
            friendHandle: payload.senderHandle,
            friendDisplayName: payload.senderDisplayName,
            stimulus: payload.stimulus,
            status: status,
            createdAt: .now
        )
        activityLog.insert(event, at: 0)
        activityContinuation?.yield(activityLog)
        return status
    }

    func simulateIncomingPoke(from friendID: Friend.ID, stimulus: StimulusConfig) async {
        guard let friend = friendsList.first(where: { $0.id == friendID }) else { return }
        let payload = PokePushPayload(
            pokeID: UUID(),
            senderHandle: friend.handle,
            senderDisplayName: friend.displayName,
            stimulus: stimulus
        )
        await handleIncomingPoke(payload)
    }

    private func seedDemoDataIfNeeded() {
        guard !didSeed else { return }
        didSeed = true

        friendsList = Self.seedFriends()
        incoming = Self.seedIncomingRequests()
        outgoing = Self.seedOutgoingRequests()
        activityLog = Self.seedActivity()

        friendsContinuation?.yield(friendsList)
        incomingContinuation?.yield(incoming)
        outgoingContinuation?.yield(outgoing)
        activityContinuation?.yield(activityLog)
    }
}

// MARK: - Demo seed data

extension MockSocialBackend {
    private static func seedFriends() -> [Friend] {
        let alicePermissionsGrantedToMe = FriendPermissionSet(
            zap: .allowed(maxIntensity: 30, cooldownSeconds: 120),
            vibe: .allowed(maxIntensity: 60, cooldownSeconds: 30),
            beep: .allowed(maxIntensity: 100, cooldownSeconds: 10)
        )
        let alicePermissionsIGranted = FriendPermissionSet(
            zap: .disabled,
            vibe: .allowed(maxIntensity: 50, cooldownSeconds: 30),
            beep: .allowed(maxIntensity: 100, cooldownSeconds: 10)
        )
        let bobPermissionsIGranted = FriendPermissionSet(
            zap: .allowed(maxIntensity: 20, cooldownSeconds: 300),
            vibe: .disabled,
            beep: .disabled
        )
        return [
            Friend(
                id: UUID(), handle: "alice", displayName: "Alice",
                permissionsGrantedToMe: alicePermissionsGrantedToMe,
                permissionsIGranted: alicePermissionsIGranted
            ),
            Friend(
                id: UUID(), handle: "bob", displayName: "Bob",
                permissionsGrantedToMe: .none,
                permissionsIGranted: bobPermissionsIGranted
            )
        ]
    }

    private static func seedIncomingRequests() -> [FriendRequest] {
        [
            FriendRequest(
                id: UUID(), handle: "charlie", displayName: "Charlie", direction: .incoming, createdAt: .now.addingTimeInterval(-3600)
            )
        ]
    }

    private static func seedOutgoingRequests() -> [FriendRequest] {
        [
            FriendRequest(
                id: UUID(), handle: "dana", displayName: "Dana", direction: .outgoing, createdAt: .now.addingTimeInterval(-7200)
            )
        ]
    }

    private static func seedActivity() -> [PokeEvent] {
        [
            PokeEvent(
                id: UUID(), direction: .received, friendHandle: "alice", friendDisplayName: "Alice",
                stimulus: StimulusConfig(kind: .vibe, intensity: 40, repetitions: 1), status: .fired,
                createdAt: .now.addingTimeInterval(-1800)
            ),
            PokeEvent(
                id: UUID(), direction: .sent, friendHandle: "bob", friendDisplayName: "Bob",
                stimulus: StimulusConfig(kind: .zap, intensity: 15, repetitions: 1), status: .fired,
                createdAt: .now.addingTimeInterval(-5400)
            )
        ]
    }
}
