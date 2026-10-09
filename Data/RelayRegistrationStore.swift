import Foundation
import Security

/// This phone's registration with a push relay, as made for one Jolt server.
struct RelayRegistration: Codable, Equatable {
    /// The Jolt server it was made for (its API base), so a server switch
    /// can tell the registration belongs to the previous one.
    var serverBaseURL: URL
    var relayURL: URL
    var serverId: String
    /// What the relay knows this phone by. Possession is enough to revoke
    /// the registration, so it lives in the keychain.
    var relayToken: String
    /// The APNs token the relay was given. A new one from Apple means
    /// registering again.
    var apnsToken: String
    /// The `kid` of the `payloadKey` handed to the server with it.
    var keyId: String
}

/// Keychain storage for the one current `RelayRegistration`, and for the
/// ones on their way out. One current, not one per server: the app talks to
/// one server at a time, and a registration for any other is revoked as soon
/// as the current one is made.
///
/// A revoked registration stays here as pending until the relay confirms
/// it: until then the relay can still push with its token, and the app has
/// to keep treating pushes as relayed (C9).
///
/// The app's own keychain group: the extension has no use for it.
struct RelayRegistrationStore {
    private let service: String
    private let currentAccount = "current"
    private let pendingAccount = "pendingUnregistration"

    init(service: String = "cz.peelco.jolt.relayRegistration") {
        self.service = service
    }

    func load() -> RelayRegistration? {
        read(currentAccount).flatMap { try? JSONDecoder().decode(RelayRegistration.self, from: $0) }
    }

    func save(_ registration: RelayRegistration) {
        guard let data = try? JSONEncoder().encode(registration) else { return }
        write(data, account: currentAccount)
    }

    func clear() {
        SecItemDelete(query(currentAccount) as CFDictionary)
    }

    /// Registrations revoked here whose revocation the relay hasn't
    /// confirmed yet, oldest first.
    func pendingUnregistrations() -> [RelayRegistration] {
        read(pendingAccount).flatMap { try? JSONDecoder().decode([RelayRegistration].self, from: $0) } ?? []
    }

    func addPendingUnregistration(_ registration: RelayRegistration) {
        var pending = pendingUnregistrations().filter { $0.relayToken != registration.relayToken }
        pending.append(registration)
        savePending(pending)
    }

    /// The relay has confirmed `relayToken` is revoked.
    func removePendingUnregistration(relayToken: String) {
        savePending(pendingUnregistrations().filter { $0.relayToken != relayToken })
    }

    private func savePending(_ pending: [RelayRegistration]) {
        guard !pending.isEmpty else {
            SecItemDelete(query(pendingAccount) as CFDictionary)
            return
        }
        guard let data = try? JSONEncoder().encode(pending) else { return }
        write(data, account: pendingAccount)
    }

    private func read(_ account: String) -> Data? {
        var query = query(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    private func write(_ data: Data, account: String) {
        // SecItemUpdate can't create, SecItemAdd can't replace — delete first
        // so this is a plain upsert.
        SecItemDelete(query(account) as CFDictionary)
        var query = query(account)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    private func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
