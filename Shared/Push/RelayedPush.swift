import CryptoKit
import Foundation

/// A push that came through the relay: `type` and `srv` in the clear, the
/// poke or test itself sealed in `enc` (protocol section 5). Opening one
/// turns it back into the `userInfo` shape a direct APNs push has, so
/// `PokePushPayload(userInfo:)` and `TestPushPayload(userInfo:)` read both
/// without knowing which way it came.
enum RelayedPush {
    enum Failure: Error, Equatable {
        /// `enc` without a usable `srv`, `type` or envelope.
        case malformed
        /// No `payloadKey` held for the sending server.
        case unknownServer
        case envelope(PushEnvelope.OpenError)
        /// The decrypted `type` disagrees with the one outside.
        case typeMismatch
        /// From a server other than the one this phone is registered with
        /// through the relay (or relayed at all, when it isn't), or one whose
        /// plaintext names a different server.
        case serverMismatch
        /// Plaintext poke or test while registered through the relay. The
        /// relay can put anything in a push it forwards; only a sealed one is
        /// known to come from the server.
        case missingEnvelope
    }

    /// What the receiver knows about how pushes should reach it.
    enum Expectation: Equatable {
        /// Not registered through the relay: only plaintext pushes, straight
        /// from the server.
        case direct
        /// Registered through the relay for this server: only pushes it
        /// sealed. The relay can put anything in a push it forwards, so a
        /// plaintext poke is refused.
        case relay(serverId: String)
        /// Any server a key is held for. The Notification Service
        /// Extension's view, which only renders text and leaves the deciding
        /// to the app.
        case anyKeyedServer
    }

    private static let kinds: Set<String> = ["poke", "test"]

    /// True when `userInfo` carries an envelope, i.e. needs opening.
    static func isRelayed(_ userInfo: [AnyHashable: Any]) -> Bool {
        userInfo["enc"] != nil
    }

    /// Decrypts `userInfo` if it is a relayed push and checks it against
    /// section 6 of the protocol: the key held for `srv`, the AAD built from
    /// `srv` and the outer `type`, the inner `type`, and the inner `serverId`.
    /// Anything without an envelope passes through untouched unless
    /// `expecting` rules it out.
    static func open(
        _ userInfo: [AnyHashable: Any],
        expecting: Expectation,
        key: (String) -> SymmetricKey?
    ) -> Result<[AnyHashable: Any], Failure> {
        guard isRelayed(userInfo) else {
            if case .relay = expecting, let type = userInfo["type"] as? String, kinds.contains(type) {
                return .failure(.missingEnvelope)
            }
            return .success(userInfo)
        }
        guard let serverId = userInfo["srv"] as? String,
              let type = userInfo["type"] as? String, kinds.contains(type),
              let envelope = PushEnvelope(userInfo["enc"]) else {
            return .failure(.malformed)
        }
        if let refusal = refusal(of: serverId, expecting: expecting) {
            return .failure(refusal)
        }
        guard let payloadKey = key(serverId) else { return .failure(.unknownServer) }

        let object: [String: Any]
        switch decrypt(envelope, with: payloadKey, serverId: serverId, kind: type) {
        case .success(let decrypted): object = decrypted
        case .failure(let failure): return .failure(failure)
        }
        guard object["type"] as? String == type else { return .failure(.typeMismatch) }
        guard let inner = object[type] as? [String: Any],
              inner["serverId"] as? String == serverId else { return .failure(.serverMismatch) }

        // The decrypted fields win over anything the relay put alongside
        // them. `enc` stays, so a copy the extension has already opened is
        // still checked again when the app handles it.
        var opened = userInfo
        for (field, value) in object {
            opened[field] = value
        }
        return .success(opened)
    }

    private static func refusal(of serverId: String, expecting: Expectation) -> Failure? {
        switch expecting {
        case .direct: return .serverMismatch
        case .relay(let expected): return expected == serverId ? nil : .serverMismatch
        case .anyKeyedServer: return nil
        }
    }

    private static func decrypt(
        _ envelope: PushEnvelope, with key: SymmetricKey, serverId: String, kind: String
    ) -> Result<[String: Any], Failure> {
        let plaintext: Data
        do {
            plaintext = try envelope.open(with: key, serverId: serverId, kind: kind)
        } catch let error as PushEnvelope.OpenError {
            return .failure(.envelope(error))
        } catch {
            return .failure(.malformed)
        }
        guard let object = try? JSONSerialization.jsonObject(with: plaintext) as? [String: Any] else {
            return .failure(.malformed)
        }
        return .success(object)
    }
}

/// What the Notification Service Extension shows instead of the generic
/// "You've been poked" text the relay sends.
struct RelayedNotificationContent {
    var title: String
    var body: String
    /// The push with its poke or test decrypted into it, for whichever
    /// handler sees the tap.
    var userInfo: [AnyHashable: Any]

    /// Nil when there is nothing to show: not a relayed push, or one that
    /// failed any check — the alert then keeps the fallback text.
    init?(
        userInfo: [AnyHashable: Any],
        key: (String) -> SymmetricKey?,
        timeZone: TimeZone = .current,
        locale: Locale = .current
    ) {
        guard RelayedPush.isRelayed(userInfo),
              case .success(let opened) = RelayedPush.open(userInfo, expecting: .anyKeyedServer, key: key) else {
            return nil
        }
        let text: PushAlertText
        if let test = TestPushPayload(userInfo: opened) {
            text = .test(test, timeZone: timeZone, locale: locale)
        } else if let poke = PokePushPayload(userInfo: opened) {
            text = .poke(poke, timeZone: timeZone, locale: locale)
        } else {
            return nil
        }
        self.title = text.title
        self.body = text.body
        self.userInfo = opened
    }
}
