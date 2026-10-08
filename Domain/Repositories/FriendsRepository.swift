import Foundation

@MainActor
protocol FriendsRepository {
    var friends: AsyncStream<[Friend]> { get }
    var incomingRequests: AsyncStream<[FriendRequest]> { get }
    var outgoingRequests: AsyncStream<[FriendRequest]> { get }

    /// This user's own shareable identifiers — shown on `AddFriendView` as
    /// text + QR so someone else can add *you*.
    var myHandle: String { get }
    var myInviteCode: String { get }
    /// The server's rules for what an unanswered automation consent means.
    /// Nil while signed out or against a server that predates them.
    var serverPolicies: ServerPolicies? { get }

    func sendRequest(handle: String) async throws
    func sendRequest(inviteCode: String) async throws
    func acceptRequest(_ id: FriendRequest.ID) async throws
    func rejectRequest(_ id: FriendRequest.ID) async throws
    func removeFriend(_ id: Friend.ID) async throws
    func updatePermission(for friendID: Friend.ID, kind: StimulusKind, permission: StimulusPermission) async throws

    /// Re-attempts the one-time fetch that normally only runs at launch (via
    /// session restore) or after a mutation. Callers that subscribe to
    /// `friends` well after launch — e.g. a sheet opened on demand — have no
    /// other way to recover if that initial fetch failed (offline, server
    /// unreachable): `friends` simply never yields again on its own.
    func refreshFriends() async
}
