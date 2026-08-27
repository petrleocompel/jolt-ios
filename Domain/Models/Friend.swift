import Foundation

struct Friend: Identifiable, Codable, Equatable {
    var id: UUID
    var handle: String
    var displayName: String
    /// What THEY allow ME to send them — determines the poke composer's options.
    var permissionsGrantedToMe: FriendPermissionSet
    /// What I allow THEM to send me — mine to edit, in `PermissionEditView`.
    var permissionsIGranted: FriendPermissionSet
}

enum FriendRequestDirection: String, Codable {
    case incoming
    case outgoing
}

struct FriendRequest: Identifiable, Codable, Equatable {
    var id: UUID
    var handle: String
    var displayName: String
    var direction: FriendRequestDirection
    var createdAt: Date
}
