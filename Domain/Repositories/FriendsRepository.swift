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

    func sendRequest(handle: String) async throws
    func sendRequest(inviteCode: String) async throws
    func acceptRequest(_ id: FriendRequest.ID) async throws
    func rejectRequest(_ id: FriendRequest.ID) async throws
    func removeFriend(_ id: Friend.ID) async throws
    func updatePermission(for friendID: Friend.ID, kind: StimulusKind, permission: StimulusPermission) async throws
}
