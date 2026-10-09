import CryptoKit
import Foundation
import Security

/// The `payloadKey` for each server this phone is registered with through the
/// relay, keyed by `serverId`, plus the one it replaced.
///
/// Every new relay registration comes with a new key (protocol C8), but a
/// push the server sealed just before it learned the new one can still be on
/// its way. So the previous key stays for `previousKeyLifetime`, and a push is
/// opened with whichever of the two its `kid` names.
///
/// In the keychain group the app shares with its Notification Service
/// Extension (`JoltKeychainAccessGroup` in each Info.plist), so the extension
/// can decrypt an alert before it is shown. After-first-unlock, because pokes
/// arrive on a locked phone; this-device-only, because a key restored onto
/// another phone belongs to a registration that phone never made.
struct PayloadKeyStore {
    static let previousKeyLifetime: TimeInterval = 24 * 60 * 60

    private let service: String
    private let accessGroup: String?
    private let now: () -> Date

    /// A key that has been replaced, and when it stops being accepted.
    private struct RetiredKey: Codable {
        var key: Data
        var expiresAt: Date
    }

    init(
        service: String = "cz.peelco.jolt.payloadKey",
        accessGroup: String? = SharedKeychain.accessGroup,
        now: @escaping () -> Date = Date.init
    ) {
        self.service = service
        self.accessGroup = accessGroup
        self.now = now
    }

    /// The key an envelope from `serverId` marked `kid` was sealed with: the
    /// current one, or the previous one while it is still accepted.
    func key(for serverId: String, kid: String) -> SymmetricKey? {
        if let current = currentKey(for: serverId), PushEnvelope.keyID(for: current) == kid {
            return current
        }
        guard let data = read(previousAccount(serverId)),
              let retired = try? JSONDecoder().decode(RetiredKey.self, from: data) else { return nil }
        guard retired.expiresAt > now() else {
            SharedKeychain.delete(baseQuery(previousAccount(serverId)))
            return nil
        }
        let previous = SymmetricKey(data: retired.key)
        return PushEnvelope.keyID(for: previous) == kid ? previous : nil
    }

    /// The key the server was handed with the current registration.
    func currentKey(for serverId: String) -> SymmetricKey? {
        guard let data = read(serverId), data.count == 32 else { return nil }
        return SymmetricKey(data: data)
    }

    /// Makes `key` the current one. A different key it replaces stays
    /// accepted for `previousKeyLifetime`.
    @discardableResult
    func save(_ key: SymmetricKey, for serverId: String) -> Bool {
        if let current = currentKey(for: serverId), PushEnvelope.keyID(for: current) != PushEnvelope.keyID(for: key) {
            retireCurrentKey(for: serverId)
        }
        return write(key.withUnsafeBytes { Data($0) }, account: serverId)
    }

    /// Demotes the current key to the previous one, for a registration that
    /// is being replaced: the server may still seal with it for a while.
    func retireCurrentKey(for serverId: String) {
        guard let current = currentKey(for: serverId) else { return }
        let retired = RetiredKey(
            key: current.withUnsafeBytes { Data($0) },
            expiresAt: now().addingTimeInterval(Self.previousKeyLifetime)
        )
        if let data = try? JSONEncoder().encode(retired) {
            write(data, account: previousAccount(serverId))
        }
        SharedKeychain.delete(baseQuery(serverId))
    }

    /// Forgets every key held for `serverId`, current and previous.
    func remove(for serverId: String) {
        SharedKeychain.delete(baseQuery(serverId))
        SharedKeychain.delete(baseQuery(previousAccount(serverId)))
    }

    private func previousAccount(_ serverId: String) -> String {
        "\(serverId)#previous"
    }

    private func read(_ account: String) -> Data? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SharedKeychain.copyMatching(query, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    @discardableResult
    private func write(_ data: Data, account: String) -> Bool {
        SharedKeychain.delete(baseQuery(account))
        var query = baseQuery(account)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SharedKeychain.add(query) == errSecSuccess
    }

    private func baseQuery(_ account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
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
