import CryptoKit
import Foundation
import Security

/// The `payloadKey` for each server this phone is registered with through the
/// relay, keyed by `serverId`.
///
/// In the keychain group the app shares with its Notification Service
/// Extension (`JoltKeychainAccessGroup` in each Info.plist), so the extension
/// can decrypt an alert before it is shown. After-first-unlock, because pokes
/// arrive on a locked phone; this-device-only, because a key restored onto
/// another phone belongs to a registration that phone never made.
struct PayloadKeyStore {
    private let service: String
    private let accessGroup: String?

    init(service: String = "cz.peelco.jolt.payloadKey", accessGroup: String? = SharedKeychain.accessGroup) {
        self.service = service
        self.accessGroup = accessGroup
    }

    func key(for serverId: String) -> SymmetricKey? {
        var query = baseQuery(for: serverId)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SharedKeychain.copyMatching(query, &item) == errSecSuccess,
              let data = item as? Data, data.count == 32 else { return nil }
        return SymmetricKey(data: data)
    }

    @discardableResult
    func save(_ key: SymmetricKey, for serverId: String) -> Bool {
        remove(for: serverId)
        var query = baseQuery(for: serverId)
        query[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SharedKeychain.add(query) == errSecSuccess
    }

    func remove(for serverId: String) {
        SharedKeychain.delete(baseQuery(for: serverId))
    }

    private func baseQuery(for serverId: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: serverId
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}

/// The keychain access group the app and its extension share.
enum SharedKeychain {
    /// From the `JoltKeychainAccessGroup` Info.plist key, which carries the
    /// team prefix only the build knows. Nil when the build left it unset.
    static let accessGroup: String? = {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "JoltKeychainAccessGroup") as? String,
              !group.isEmpty, !group.contains("$(") else { return nil }
        return group
    }()

    // A build signed without the shared group in its entitlements (ad hoc on
    // CI, or a self-builder's free team) gets errSecMissingEntitlement for
    // any query that names it. Retrying in the app's own group keeps the app
    // decrypting pokes itself; only the extension's rewrite of the alert is
    // lost, and it falls back to the generic text.

    static func copyMatching(_ query: [String: Any], _ result: UnsafeMutablePointer<CFTypeRef?>) -> OSStatus {
        let status = SecItemCopyMatching(query as CFDictionary, result)
        guard status == errSecMissingEntitlement else { return status }
        return SecItemCopyMatching(withoutGroup(query) as CFDictionary, result)
    }

    static func add(_ query: [String: Any]) -> OSStatus {
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecMissingEntitlement else { return status }
        return SecItemAdd(withoutGroup(query) as CFDictionary, nil)
    }

    static func delete(_ query: [String: Any]) {
        if SecItemDelete(query as CFDictionary) == errSecMissingEntitlement {
            SecItemDelete(withoutGroup(query) as CFDictionary)
        }
    }

    private static func withoutGroup(_ query: [String: Any]) -> [String: Any] {
        var query = query
        query.removeValue(forKey: kSecAttrAccessGroup as String)
        return query
    }
}
