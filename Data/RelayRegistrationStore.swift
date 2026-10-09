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

/// Keychain storage for the one current `RelayRegistration`. One, not one
/// per server: the app talks to one server at a time, and a registration
/// for any other is revoked as soon as the current one is made.
///
/// The app's own keychain group: the extension has no use for it.
struct RelayRegistrationStore {
    private let service: String
    private let account = "current"

    init(service: String = "cz.peelco.jolt.relayRegistration") {
        self.service = service
    }

    func load() -> RelayRegistration? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(RelayRegistration.self, from: data)
    }

    func save(_ registration: RelayRegistration) {
        guard let data = try? JSONEncoder().encode(registration) else { return }
        clear()
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
