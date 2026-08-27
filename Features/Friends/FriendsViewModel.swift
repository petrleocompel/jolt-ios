import Foundation
import Observation

@MainActor
@Observable
final class FriendsViewModel {
    private let repository: FriendsRepository

    private(set) var friends: [Friend] = []
    private(set) var incomingRequests: [FriendRequest] = []
    private(set) var outgoingRequests: [FriendRequest] = []
    var lastError: String?

    var myHandle: String { repository.myHandle }
    var myInviteCode: String { repository.myInviteCode }

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
            for await value in repository.friends { self.friends = value }
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

    func updatePermission(for friend: Friend, kind: StimulusKind, permission: StimulusPermission) {
        Task { try? await repository.updatePermission(for: friend.id, kind: kind, permission: permission) }
    }
}
