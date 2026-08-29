import Foundation
import Observation

/// Drives the optional **Pavlok account** section: sign in, list Pavlok
/// friends, poke them, and show a best-effort device-activity feed.
///
/// Kept entirely separate from the Jolt-server social stack (`FriendsViewModel`
/// / `PokeRepository`). The two backends have different ids, permission models
/// and capabilities, and the user asked for them not to be conflated.
///
/// **Receiving pokes is not possible here** — Pavlok delivers incoming pokes
/// only as a Firebase push to their own app, and nothing server-side records
/// them (see `docs/PAVLOK-API.md`). What this shows instead is the wearable's
/// own uploaded stimulus log, which has no sender, and the UI says so plainly.
@MainActor
@Observable
final class PavlokAccountViewModel {
    private let client: PavlokAPIClient
    private let store: PavlokCredentialStore

    private(set) var account: PavlokAccount?
    private(set) var friends: [PavlokFriend] = []
    /// Keyed by friend id — what each friend allows me to send them.
    private(set) var permissions: [Int: PavlokPokePermission] = [:]
    private(set) var activity: [PavlokStimulusLogEntry] = []

    private(set) var isLoading = false
    private(set) var isSending = false
    var lastError: String?
    private(set) var lastSentMessage: String?

    /// MAC of the device whose journal we show. First device by default.
    private(set) var journalMACAddress: String?

    var isSignedIn: Bool { account != nil }

    init(client: PavlokAPIClient = PavlokAPIClient(), store: PavlokCredentialStore = PavlokCredentialStore()) {
        self.client = client
        self.store = store
        self.account = store.savedAccount
    }

    /// Restores a saved session, if any, and loads the friends list.
    func restore() async {
        guard let token = store.token, account != nil else { return }
        await client.setToken(token)
        await refresh()
    }

    func signIn(email: String, password: String) async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        do {
            let result = try await client.login(email: email, password: password)
            await client.setToken(result.token)
            store.save(token: result.token, account: result.account)
            account = result.account
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func signOut() {
        store.clear()
        account = nil
        friends = []
        permissions = [:]
        activity = []
        journalMACAddress = nil
        Task { await client.setToken(nil) }
    }

    func refresh() async {
        guard isSignedIn else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let friendList = client.friends()
            async let grants = client.receivedPokePermissions()
            friends = try await friendList
            permissions = try await grants
            lastError = nil
        } catch let error as PavlokAPIClient.APIError {
            handle(error)
        } catch {
            lastError = error.localizedDescription
        }
        await refreshActivity()
    }

    /// Best-effort activity: the wearable's own log. Not poke attribution.
    func refreshActivity() async {
        guard isSignedIn else { return }
        do {
            if journalMACAddress == nil {
                journalMACAddress = try await client.devices().first?.macAddress
            }
            guard let mac = journalMACAddress else { return }
            activity = try await client.stimulusJournal(macAddress: mac)
        } catch let error as PavlokAPIClient.APIError {
            handle(error)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func permission(for friend: PavlokFriend) -> PavlokPokePermission {
        permissions[friend.id] ?? .none
    }

    /// Sends a poke, clamped to what the recipient allows. Returns silently
    /// when the stimulus isn't permitted — the UI disables those options, so
    /// reaching here means state changed underneath us.
    func poke(_ friend: PavlokFriend, stimulus: StimulusConfig) async {
        let grant = permission(for: friend)
        guard grant.allows(stimulus.kind) else {
            lastError = "\(friend.displayName) hasn't allowed \(stimulus.kind.displayName.lowercased())."
            return
        }
        let clamped = StimulusConfig(
            kind: stimulus.kind,
            intensity: min(stimulus.intensity, grant.maxIntensity(for: stimulus.kind)),
            repetitions: stimulus.repetitions
        )
        isSending = true
        lastError = nil
        defer { isSending = false }
        do {
            try await client.sendPoke(to: friend.id, stimulus: clamped)
            lastSentMessage = "Sent \(clamped.kind.displayName.lowercased()) to \(friend.displayName)"
        } catch let error as PavlokAPIClient.APIError {
            handle(error)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func handle(_ error: PavlokAPIClient.APIError) {
        lastError = error.localizedDescription
        // An expired Pavlok JWT should drop us back to the sign-in form rather
        // than leaving a signed-in shell that fails every request.
        if error == .unauthorized { signOut() }
    }
}
