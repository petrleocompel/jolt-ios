import CryptoKit
import Foundation

/// The encrypted payload a relayed push carries in its `enc` field — section 6
/// of the relay protocol (`jolt-relay/spec/protocol-v1.md`).
///
/// AES-256-GCM under the `payloadKey` this phone generated when it registered
/// with the relay, so the relay forwards pokes it cannot read. The additional
/// data binds each ciphertext to the server that sealed it and to the kind of
/// message, so neither can be swapped on the way through.
struct PushEnvelope: Equatable {
    static let version = 1
    private static let nonceLength = 12
    private static let tagLength = 16

    /// Which key sealed it: the first 8 bytes of SHA-256(payloadKey).
    var kid: String
    var nonce: Data
    /// Ciphertext with the 16-byte GCM tag appended.
    var ciphertext: Data

    enum OpenError: Error, Equatable {
        case unsupportedVersion
        case malformed
        /// Sealed with a key other than the one held for this server — an
        /// older registration, most likely.
        case keyMismatch
        /// The tag didn't verify: wrong key, wrong server or wrong kind in the
        /// additional data, or a tampered ciphertext.
        case authenticationFailed
    }

    init(kid: String, nonce: Data, ciphertext: Data) {
        self.kid = kid
        self.nonce = nonce
        self.ciphertext = ciphertext
    }

    /// Parses the `enc` object out of a push's `userInfo`. Nil for anything
    /// that isn't a well-formed version 1 envelope.
    init?(_ object: Any?) {
        guard let dict = object as? [String: Any],
              (dict["v"] as? NSNumber)?.intValue == Self.version,
              let kid = dict["kid"] as? String,
              let nonce = (dict["n"] as? String).flatMap(Base64URL.decode),
              let ciphertext = (dict["ct"] as? String).flatMap(Base64URL.decode),
              nonce.count == Self.nonceLength,
              ciphertext.count >= Self.tagLength else { return nil }
        self.init(kid: kid, nonce: nonce, ciphertext: ciphertext)
    }

    /// The `enc` object as it travels.
    var jsonObject: [String: Any] {
        ["v": Self.version, "kid": kid, "n": Base64URL.encode(nonce), "ct": Base64URL.encode(ciphertext)]
    }

    static func keyID(for key: SymmetricKey) -> String {
        let digest = key.withUnsafeBytes { SHA256.hash(data: Data($0)) }
        return Base64URL.encode(Data(digest.prefix(8)))
    }

    /// `jolt-push-v1|<serverId>|<kind>`.
    static func additionalData(serverId: String, kind: String) -> Data {
        Data("jolt-push-v1|\(serverId)|\(kind)".utf8)
    }

    func open(with key: SymmetricKey, serverId: String, kind: String) throws -> Data {
        guard kid == Self.keyID(for: key) else { throw OpenError.keyMismatch }
        do {
            let box = try AES.GCM.SealedBox(combined: nonce + ciphertext)
            return try AES.GCM.open(
                box, using: key,
                authenticating: Self.additionalData(serverId: serverId, kind: kind)
            )
        } catch CryptoKitError.authenticationFailure {
            throw OpenError.authenticationFailed
        } catch {
            throw OpenError.malformed
        }
    }

    /// The server's half, here so tests can build envelopes the vectors
    /// don't cover.
    static func seal(
        _ plaintext: Data,
        with key: SymmetricKey,
        serverId: String,
        kind: String,
        nonce: AES.GCM.Nonce = AES.GCM.Nonce()
    ) throws -> PushEnvelope {
        let box = try AES.GCM.seal(
            plaintext, using: key, nonce: nonce,
            authenticating: additionalData(serverId: serverId, kind: kind)
        )
        return PushEnvelope(kid: keyID(for: key), nonce: Data(nonce), ciphertext: box.ciphertext + box.tag)
    }
}
