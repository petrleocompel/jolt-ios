import Foundation

/// Persists per-friend poke composer drafts (kind + intensity) in one
/// `UserDefaults` dictionary keyed by friend ID.
struct FriendPokeDraftStore {
    private let defaults: UserDefaults
    private let key = "cz.peelco.jolt.friendPokeDrafts"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(friendID: Friend.ID) -> FriendPokeDraft? {
        all()[friendID.uuidString]
    }

    func save(_ draft: FriendPokeDraft, for friendID: Friend.ID) {
        var drafts = all()
        drafts[friendID.uuidString] = draft
        guard let data = try? JSONEncoder().encode(drafts) else { return }
        defaults.set(data, forKey: key)
    }

    func reset() {
        defaults.removeObject(forKey: key)
    }

    private func all() -> [String: FriendPokeDraft] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: FriendPokeDraft].self, from: data) else {
            return [:]
        }
        return decoded
    }
}
