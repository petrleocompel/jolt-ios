import Foundation
import Security

/// Keychain storage for the Pavlok account's JWT, plus the account summary.
///
/// Same reasoning as `AuthTokenStore`: the token authenticates every request as
/// the user, so it does not belong in `UserDefaults` (a plist that lands in
/// unencrypted backups). The non-secret account summary — id, email, name — is
/// kept in `UserDefaults` so the UI can show who is signed in without touching
/// the keychain on every render.
struct PavlokCredentialStore {
    private let service = "cz.peelco.jolt.pavlokToken"
    private let account = "api.pavlok.com"
    private let accountKey = "cz.peelco.jolt.pavlokAccount"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var token: String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    var savedAccount: PavlokAccount? {
        guard let data = defaults.data(forKey: accountKey) else { return nil }
        return try? JSONDecoder().decode(PavlokAccount.self, from: data)
    }

    func save(token: String, account: PavlokAccount) {
        if let data = token.data(using: .utf8) {
            // SecItemAdd can't replace and SecItemUpdate can't create, so
            // delete first to make this a plain upsert.
            SecItemDelete(baseQuery as CFDictionary)
            var query = baseQuery
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(query as CFDictionary, nil)
        }
        if let encoded = try? JSONEncoder().encode(account) {
            defaults.set(encoded, forKey: accountKey)
        }
    }

    func clear() {
        SecItemDelete(baseQuery as CFDictionary)
        defaults.removeObject(forKey: accountKey)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
