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
        /// No `payloadKey` held for the sending server under the envelope's
        /// `kid`: not registered with it, or a key retired more than a day
        /// ago.
        case unknownKey
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
        /// `sentAt` missing, older than `maximumAge`, or further ahead than
        /// `allowedClockSkew`. A relay that kept a sealed push can send it
        /// again later, and it would still open.
        case stale
    }

    /// How old a relayed push may be: the server gives pokes and tests 300
    /// seconds to live, because a stimulus that arrives late is worse than
    /// one that never does (C4). Apple enforces that for a direct push; for a
    /// relayed one only this check does.
    static let maximumAge: TimeInterval = 300
    /// How far ahead of this phone's clock the server's may run.
    static let allowedClockSkew: TimeInterval = 60

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
    /// section 6 of the protocol: the key held for `srv` and `kid`, the AAD
    /// built from `srv` and the outer `type`, the inner `type`, and the inner
    /// `serverId`. Anything without an envelope passes through untouched
    /// unless `expecting` rules it out (C9).
    ///
    /// A relayed poke or test must also be fresh: see `maximumAge`.
    ///
    /// - Parameter key: the key held for a `serverId` and `kid`, if any.
    static func open(
        _ userInfo: [AnyHashable: Any],
        expecting: Expectation,
        now: Date = Date(),
        key: (_ serverId: String, _ kid: String) -> SymmetricKey?
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
        guard let payloadKey = key(serverId, envelope.kid) else { return .failure(.unknownKey) }

        let object: [String: Any]
        switch decrypt(envelope, with: payloadKey, serverId: serverId, kind: type) {
        case .success(let decrypted): object = decrypted
        case .failure(let failure): return .failure(failure)
        }
        if let refusal = refusal(of: object, type: type, serverId: serverId, now: now) {
            return .failure(refusal)
        }

        // The decrypted fields win over anything the relay put alongside
        // them. `enc` stays, so a copy the extension has already opened is
        // still checked again when the app handles it.
        var opened = userInfo
        for (field, value) in object {
            opened[field] = value
        }
        return .success(opened)
    }

    /// The checks on what the envelope held: the same `type` as outside, the
    /// sending server's `serverId`, and a fresh `sentAt`.
    private static func refusal(of object: [String: Any], type: String, serverId: String, now: Date) -> Failure? {
        guard object["type"] as? String == type else { return .typeMismatch }
        guard let inner = object[type] as? [String: Any],
              inner["serverId"] as? String == serverId else { return .serverMismatch }
        guard isFresh(inner["sentAt"] as? String, now: now) else { return .stale }
        return nil
    }

    private static func isFresh(_ sentAt: String?, now: Date) -> Bool {
        guard let sentAt, let sent = PushAlertText.parseTimestamp(sentAt) else { return false }
        let age = now.timeIntervalSince(sent)
        return age <= maximumAge && age >= -allowedClockSkew
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
    /// failed any check, staleness included — the alert then keeps the
    /// fallback text.
    init?(
        userInfo: [AnyHashable: Any],
        key: (_ serverId: String, _ kid: String) -> SymmetricKey?,
        now: Date = Date(),
        timeZone: TimeZone = .current,
        locale: Locale = .current
    ) {
        guard RelayedPush.isRelayed(userInfo),
              case .success(let opened) = RelayedPush.open(userInfo, expecting: .anyKeyedServer, now: now, key: key) else {
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
