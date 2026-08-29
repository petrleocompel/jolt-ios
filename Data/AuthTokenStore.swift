import Foundation
import Security

/// Keychain storage for the bearer token issued by a Jolt Server.
///
/// Keychain rather than `UserDefaults`: the token authenticates every request
/// as the user, and `UserDefaults` is a plist inside the app container that
/// lands in unencrypted backups. `kSecAttrAccessibleAfterFirstUnlock` so a
/// silent poke push can still be acked while the phone is locked.
///
/// Scoped per server — the account is the base URL — so switching servers and
/// switching back doesn't require signing in again, and one server can never
/// see a token issued by another.
struct AuthTokenStore {
    private let service = "cz.peelco.jolt.authToken"

    func token(for server: ServerConfiguration) -> String? {
        var query = baseQuery(for: server)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(_ token: String, for server: ServerConfiguration) {
        guard let data = token.data(using: .utf8) else { return }
        // SecItemUpdate can't create, SecItemAdd can't replace — delete first
        // so this is a plain upsert.
        SecItemDelete(baseQuery(for: server) as CFDictionary)
        var query = baseQuery(for: server)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    func clear(for server: ServerConfiguration) {
        SecItemDelete(baseQuery(for: server) as CFDictionary)
    }

    private func baseQuery(for server: ServerConfiguration) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: server.baseURL.absoluteString
        ]
    }
}
