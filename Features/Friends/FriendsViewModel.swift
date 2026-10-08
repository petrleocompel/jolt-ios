import Foundation
import Observation

@MainActor
@Observable
final class FriendsViewModel {
    private let repository: FriendsRepository

    private(set) var friends: [Friend] = []
    private(set) var incomingRequests: [FriendRequest] = []
    private(set) var outgoingRequests: [FriendRequest] = []
    /// Flips true after the first emission from `repository.friends`, so
    /// callers can tell "not loaded yet" apart from "loaded and genuinely
    /// empty/missing" — an empty `friends` array means both until this fires.
    private(set) var hasLoadedFriends = false
    var lastError: String?

    var myHandle: String { repository.myHandle }
    var myInviteCode: String { repository.myInviteCode }
    /// Nil against a server too old to have automation consent at all.
    var serverPolicies: ServerPolicies? { repository.serverPolicies }

    @ObservationIgnored
    nonisolated(unsafe) private var friendsTask: Task<Void, Never>?
    @ObservationIgnored
    nonisolated(unsafe) private var incomingTask: Task<Void, Never>?
    @ObservationIgnored
    nonisolated(unsafe) private var outgoingTask: Task<Void, Never>?

    init(repository: FriendsRepository) {
        self.repository = repository
        friendsTask = Task { [weak self] in
            guard let self else { return }
            for await value in repository.friends {
                self.friends = value
                self.hasLoadedFriends = true
            }
        }
        incomingTask = Task { [weak self] in
            guard let self else { return }
            for await value in repository.incomingRequests { self.incomingRequests = value }
        }
        outgoingTask = Task { [weak self] in
            guard let self else { return }
            for await value in repository.outgoingRequests { self.outgoingRequests = value }
        }
    }

    deinit {
        friendsTask?.cancel()
        incomingTask?.cancel()
        outgoingTask?.cancel()
    }

    func sendRequest(handle: String) async {
        lastError = nil
        do {
            try await repository.sendRequest(handle: handle)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func sendRequest(inviteCode: String) async {
        lastError = nil
        do {
            try await repository.sendRequest(inviteCode: inviteCode)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func accept(_ request: FriendRequest) {
        Task { try? await repository.acceptRequest(request.id) }
    }

    func reject(_ request: FriendRequest) {
        Task { try? await repository.rejectRequest(request.id) }
    }

    func remove(_ friend: Friend) {
        Task { try? await repository.removeFriend(friend.id) }
    }

    /// Retries the friends fetch. Needed when a caller subscribes well after
    /// launch (e.g. a sheet opened on demand) and the one-time launch fetch
    /// already failed — `friends` otherwise never yields again on its own.
    func refresh() async {
        await repository.refreshFriends()
    }

    /// Updates `friends` locally before the network call returns, not just
    /// after. `PermissionEditView`'s "Allow" toggle and its two steppers
    /// each capture a `StimulusPermission` snapshot at render time and send
    /// a full overwrite of it — flip "Allow" on and immediately bump the
    /// intensity stepper (a natural sequence) and, without this, the second
    /// write could fire before the first one's server round trip refreshed
    /// `friends`, so it would still be holding the pre-toggle snapshot and
    /// silently revert `isAllowed` back to false. Applying the change here
    /// first means every subsequent render — and thus every subsequent
    /// binding closure — reads the latest known state immediately.
    ///
    /// Touches the grant only. The automation answer stays as it is here
    /// and on the server — a preset's value carries none, and must not
    /// look like it reset one.
    func updatePermission(for friend: Friend, kind: StimulusKind, permission: StimulusPermission) {
        let previous = currentPermission(of: friend, kind: kind) ?? friend.permissionsIGranted[kind]
        if let index = friends.firstIndex(where: { $0.id == friend.id }) {
            friends[index].permissionsIGranted[kind] = permission.keepingAutomationConsent(of: previous)
        }
        Task {
            do {
                try await repository.updatePermission(for: friend.id, kind: kind, permission: permission)
            } catch {
                // The save failed server-side — don't leave the toggle showing
                // a state that was never actually persisted. Only the grant
                // goes back: an automation answer made meanwhile is its own
                // request.
                if let index = friends.firstIndex(where: { $0.id == friend.id }) {
                    let now = friends[index].permissionsIGranted[kind]
                    friends[index].permissionsIGranted[kind] = previous.keepingAutomationConsent(of: now)
                }
                lastError = error.localizedDescription
            }
        }
    }

    /// Answers "may this friend's scripts send me `kind`?" — nil hands it
    /// back to the server's default. Optimistic for the same reason as
    /// `updatePermission`, and the mirror image on failure: only the answer
    /// is rolled back, never a grant edit that raced it.
    func updateAutomationConsent(for friend: Friend, kind: StimulusKind, allowed: Bool?) {
        guard let index = friends.firstIndex(where: { $0.id == friend.id }) else { return }
        let previous = friends[index].permissionsIGranted[kind]
        var updated = previous
        updated.automationAllowed = allowed
        // What the server will report back, so the picker's "Default (…)"
        // reads right before the refresh lands.
        updated.automationAllowedEffective = allowed
            ?? serverPolicies?.automationAllowedByDefault
            ?? previous.automationAllowedEffective
        friends[index].permissionsIGranted[kind] = updated
        Task {
            do {
                try await repository.updateAutomationConsent(
                    for: friend.id, kind: kind, permission: updated, allowed: allowed
                )
            } catch {
                if let index = friends.firstIndex(where: { $0.id == friend.id }) {
                    let now = friends[index].permissionsIGranted[kind]
                    friends[index].permissionsIGranted[kind] = now.keepingAutomationConsent(of: previous)
                }
                lastError = error.localizedDescription
            }
        }
    }

    private func currentPermission(of friend: Friend, kind: StimulusKind) -> StimulusPermission? {
        friends.first(where: { $0.id == friend.id })?.permissionsIGranted[kind]
    }
}
