import CryptoKit
import Foundation

/// Everything the relay path of push registration needs besides the Jolt
/// server, gathered so tests can replace it: which relays to trust, App
/// Attest, where keys and the registration are kept, and the network.
@MainActor
struct RelayEnvironment {
    var trustedHosts: TrustedRelayHosts
    var attestor: AppAttesting
    var keys: PayloadKeyStore
    var registrations: RelayRegistrationStore
    var session: URLSession
    /// The bundle ID the relay checks against its allow-list.
    var appId: String
    /// `production` or `sandbox`: which APNs environment issued this build's
    /// tokens.
    var apnsEnvironment: String
    /// How long the relay has asked to be left alone (C21).
    var backoff = RelayBackoff()

    static var live: RelayEnvironment {
        RelayEnvironment(
            trustedHosts: .bundled,
            attestor: AppAttestor(),
            keys: PayloadKeyStore(),
            registrations: RelayRegistrationStore(),
            session: .shared,
            appId: Bundle.main.bundleIdentifier ?? "cz.peelco.jolt",
            apnsEnvironment: apnsEnvironment(from: Bundle.main.object(forInfoDictionaryKey: "JoltAPSEnvironment"))
        )
    }

    /// The entitlement says `development`, the relay says `sandbox`.
    static func apnsEnvironment(from infoValue: Any?) -> String {
        infoValue as? String == "development" ? "sandbox" : "production"
    }
}

/// Telling the server how to reach this phone, and taking it back again.
/// Kept out of `HTTPSocialBackend.swift` so neither file grows past readable
/// size.
///
/// The server decides the route (`GET /push/config`): its own APNs
/// credentials, the relay, or nothing. Through the relay, the phone registers
/// its APNs token with the relay, generates a `payloadKey` and hands the
/// server only the relay's token and that key — so the server never sees the
/// APNs token, and the relay never sees what is in a poke.
///
/// Nothing here goes through the `send` wrappers: a 401 there logs out, and
/// logging out waits for `pushRegistrationQueue`, which would be waiting for
/// the very call that 401'd.
extension HTTPSocialBackend {
    struct PushTokenBody: Encodable {
        let token: String
        let platform = "ios"
    }

    struct RelayPushTokenBody: Encodable {
        let transport = "relay"
        let platform = "ios"
        let relayToken: String
        let payloadKey: String
        let keyId: String
    }

    /// One of the two set: the APNs token for a direct registration, or the
    /// relay's token for a relayed one.
    struct ForgetPushTokenBody: Encodable {
        var token: String?
        var relayToken: String?
    }

    func registerPushToken(_ token: String) async {
        lastPushToken = token
        // Nothing to attach it to yet; whoever signs in (or the session
        // restore) sends it. Remembered either way — see `lastPushToken`.
        guard isSignedIn else { return }
        await registerPush(replacingRelayRegistration: false)
    }

    /// Re-asserts this phone's registration for whoever is signed in now.
    /// Idempotent server-side (the token is the conflict target), so calling
    /// it on every identity change costs a request or two and buys the
    /// guarantee that the binding matches the session.
    func registerLastPushToken() async {
        guard lastPushToken != nil else { return }
        await registerPush(replacingRelayRegistration: false)
    }

    /// Registers again from scratch, after a poke arrived that wasn't for
    /// this account (`HTTPSocialBackend+Pokes.swift`). Through the relay that
    /// means a new `relayToken`, which also revokes the old one: whoever the
    /// server still had it bound to can't reach this phone with it anymore.
    func reregisterPush() async {
        guard lastPushToken != nil else { return }
        await registerPush(replacingRelayRegistration: true)
    }

    /// Revokes a relay registration made for a server the user has since
    /// switched away from. Run at launch, before anything signs in: until
    /// then the old server could still reach this phone through the relay.
    /// The app would refuse what it sent, but the extension would show it.
    func retireRelayRegistrationForAnotherServer() async {
        guard let stored = relay.registrations.load(), stored.serverBaseURL != configuration.baseURL else { return }
        await serialized { await self.retireRelayRegistration() }
    }

    /// Undoes every registration this phone holds, on sign-out: the server's
    /// binding, the relay's, and the key.
    func unregisterPush() async {
        await pushRegistrationQueue?.value
        await retireRelayRegistration()
        if let lastPushToken, isSignedIn {
            try? await client.sendIgnoringResponse(
                "DELETE", "devices/push-token",
                body: ForgetPushTokenBody(token: lastPushToken)
            )
        }
        pushRegistration = PushRegistrationState()
    }

    /// The `userInfo` a poke or test handler should read: a relayed push
    /// decrypted, a direct one as it came. Nil when it must be dropped — see
    /// `RelayedPush.Failure`.
    func openIncomingPush(_ userInfo: [AnyHashable: Any]) -> [AnyHashable: Any]? {
        let expecting: RelayedPush.Expectation = if let registration = currentRelayRegistration {
            .relay(serverId: registration.serverId)
        } else {
            .direct
        }
        switch RelayedPush.open(userInfo, expecting: expecting, key: relay.keys.key(for:kid:)) {
        case .success(let opened):
            return opened
        case .failure(let failure):
            print("[Jolt] dropped a push that failed to open: \(failure)")
            return nil
        }
    }

    /// The stored registration, if it was made for the server this backend
    /// talks to. One for a server the user has since switched away from is
    /// about to be revoked, and doesn't vouch for anything meanwhile.
    private var currentRelayRegistration: RelayRegistration? {
        guard let registration = relay.registrations.load(),
              registration.serverBaseURL == configuration.baseURL else { return nil }
        return registration
    }

    private func registerPush(replacingRelayRegistration: Bool) async {
        await serialized {
            await self.performPushRegistration(replacingRelayRegistration: replacingRelayRegistration)
        }
    }

    /// Runs `operation` once every registration queued before it is done.
    private func serialized(_ operation: @escaping @MainActor () async -> Void) async {
        let previous = pushRegistrationQueue
        let task = Task {
            await previous?.value
            await operation()
        }
        pushRegistrationQueue = task
        await task.value
    }

    private func performPushRegistration(replacingRelayRegistration: Bool) async {
        guard isSignedIn, let apnsToken = lastPushToken else { return }
        let config: PushConfig
        do {
            config = try await client.send("GET", "push/config")
        } catch JoltAPIClient.APIError.server(404, _) {
            config = .legacy
        } catch {
            // Offline, most likely. Whatever was registered before stays as
            // it is; the next sign-in, restore or token asks again.
            pushRegistration.problem = "Couldn't ask the server how it sends notifications: "
                + error.localizedDescription
            return
        }

        switch config.transport {
        case .apns:
            await retireRelayRegistration()
            await registerDirectly(apnsToken)
        case .none:
            await retireRelayRegistration()
            pushRegistration = PushRegistrationState(transport: .none)
        case .relay:
            guard let target = config.relay else {
                pushRegistration = PushRegistrationState(problem: "The server uses a relay but didn't say which one.")
                return
            }
            await registerThroughRelay(target, apnsToken: apnsToken, replacing: replacingRelayRegistration)
        case .unsupported(let name):
            // An error, not a reason to tear down what works (C18).
            pushRegistration.problem = "The server delivers notifications a way this version of Jolt "
                + "doesn't know (\(name)). Updating the app should fix it."
        }
    }

    private func registerDirectly(_ apnsToken: String) async {
        do {
            try await client.sendIgnoringResponse("POST", "devices/push-token", body: PushTokenBody(token: apnsToken))
            pushRegistration = PushRegistrationState(transport: .apns, registeredToken: apnsToken)
        } catch {
            pushRegistration = PushRegistrationState(
                transport: .apns,
                problem: "The server didn't take this phone's token: \(error.localizedDescription)"
            )
        }
    }

    /// What became of handing the server a relay registration.
    private enum RelayTokenOutcome {
        case accepted
        case failed
        /// `410 relay_token_revoked`: the relay has dropped this registration
        /// and the server won't take it back (C6).
        case revoked
    }

    private func registerThroughRelay(_ target: PushConfig.Relay, apnsToken: String, replacing: Bool) async {
        guard relay.trustedHosts.allows(target.url) else {
            // An error like an unknown transport (C18), and what works stays:
            // a registration only goes once a replacement has been accepted,
            // or when the server says it no longer uses a relay.
            let problem = "The server's relay (\(target.url.host() ?? target.url.absoluteString)) "
                + "isn't one this app trusts, so this phone can't register with it."
            if currentRelayRegistration != nil {
                pushRegistration.problem = problem
            } else {
                pushRegistration = PushRegistrationState(transport: .relay(serverId: target.serverId), problem: problem)
            }
            return
        }
        guard await registerOrReassert(target, apnsToken: apnsToken, replacing: replacing) == .revoked else { return }

        // The relay dropped the registration (Apple retired the token, or an
        // admin revoked it) and the server has said so. Nothing about it is
        // worth keeping, the key included: start over, once.
        await retireRelayRegistration()
        if await registerOrReassert(target, apnsToken: apnsToken, replacing: true) == .revoked {
            pushRegistration.problem = "The server refused a fresh relay registration as revoked."
        }
    }

    /// Re-asserts the stored registration while server, relay, APNs token
    /// and key all still match it; registers afresh otherwise.
    private func registerOrReassert(
        _ target: PushConfig.Relay, apnsToken: String, replacing: Bool
    ) async -> RelayTokenOutcome {
        if !replacing, let current = currentRelayRegistration,
           current.relayURL == target.url, current.serverId == target.serverId, current.apnsToken == apnsToken,
           let key = relay.keys.currentKey(for: current.serverId), PushEnvelope.keyID(for: key) == current.keyId {
            return await sendRelayToken(current, key: key)
        }
        guard let (registration, key) = await makeRelayRegistration(target, apnsToken: apnsToken) else {
            return .failed
        }
        return await sendRelayToken(registration, key: key)
    }

    /// Registers this phone with the relay afresh and stores the new
    /// registration and key, then retires whatever it replaces. Nil when the
    /// relay couldn't be reached, asked to be left alone for a while, or the
    /// key couldn't be kept — in each case the current registration, if any,
    /// is untouched (C21).
    private func makeRelayRegistration(
        _ target: PushConfig.Relay, apnsToken: String
    ) async -> (RelayRegistration, SymmetricKey)? {
        let transport = PushTransport.relay(serverId: target.serverId)
        if let until = relay.backoff.until {
            pushRegistration.problem = Self.backoffProblem(until: until)
            return nil
        }
        let relayClient = RelayClient(baseURL: target.url, session: relay.session, attestor: relay.attestor)
        let relayToken: String
        do {
            relayToken = try await relayClient.register(
                apnsToken: apnsToken, environment: relay.apnsEnvironment,
                appId: relay.appId, serverId: target.serverId
            )
        } catch RelayClient.RelayError.rateLimited(let seconds) {
            relay.backoff.wait(seconds)
            pushRegistration.problem = relay.backoff.until.map { Self.backoffProblem(until: $0) }
            return nil
        } catch {
            pushRegistration = PushRegistrationState(
                transport: transport,
                problem: "Couldn't register with the relay: \(error.localizedDescription)"
            )
            return nil
        }

        let replaced = relay.registrations.load()
        let replacedThisServer = currentRelayRegistration != nil
        // Saving demotes a key held for the same server to the previous one,
        // kept for a day for pushes it already sealed (C8).
        let key = SymmetricKey(size: .bits256)
        guard relay.keys.save(key, for: target.serverId) else {
            try? await relayClient.unregister(relayToken: relayToken)
            pushRegistration = PushRegistrationState(
                transport: transport,
                problem: "Couldn't store the key notifications are decrypted with."
            )
            return nil
        }
        let registration = RelayRegistration(
            serverBaseURL: configuration.baseURL, relayURL: target.url, serverId: target.serverId,
            relayToken: relayToken, apnsToken: apnsToken, keyId: PushEnvelope.keyID(for: key)
        )
        relay.registrations.save(registration)

        // The registration this replaces goes on both sides, or the phone
        // gets every poke twice (C7).
        if let replaced {
            let sameServer = replaced.serverBaseURL == configuration.baseURL && replaced.serverId == target.serverId
            await revoke(replaced, droppingKey: !sameServer)
        }
        if !replacedThisServer {
            // No relay registration for this server before, so it may have
            // known this phone by its APNs token until it moved to the relay.
            try? await client.sendIgnoringResponse(
                "DELETE", "devices/push-token",
                body: ForgetPushTokenBody(token: apnsToken)
            )
        }
        return (registration, key)
    }

    private static func backoffProblem(until: Date) -> String {
        "The relay asked this phone to wait until \(until.formatted(date: .omitted, time: .shortened)) "
            + "before registering again. Notifications keep arriving the current way meanwhile."
    }

    private func sendRelayToken(_ registration: RelayRegistration, key: SymmetricKey) async -> RelayTokenOutcome {
        let transport = PushTransport.relay(serverId: registration.serverId)
        let body = RelayPushTokenBody(
            relayToken: registration.relayToken,
            payloadKey: key.withUnsafeBytes { Base64URL.encode(Data($0)) },
            keyId: registration.keyId
        )
        do {
            try await client.sendIgnoringResponse("POST", "devices/push-token", body: body)
            pushRegistration = PushRegistrationState(transport: transport, registeredToken: registration.relayToken)
            return .accepted
        } catch JoltAPIClient.APIError.server(410, _) {
            // The endpoint's only 410 is `relay_token_revoked` (C6).
            return .revoked
        } catch {
            pushRegistration = PushRegistrationState(
                transport: transport,
                problem: "The server didn't take the relay registration: \(error.localizedDescription)"
            )
            return .failed
        }
    }

    /// Revokes the stored relay registration everywhere it can, and forgets
    /// it and its key.
    private func retireRelayRegistration() async {
        guard let registration = relay.registrations.load() else { return }
        await revoke(registration, droppingKey: true)
        relay.registrations.clear()
    }

    /// Revokes `registration` on the server and the relay. The server's side
    /// only when it is the server the registration was made for: that's the
    /// only one this session can authenticate to, and for any other the relay
    /// revocation is what counts — the old server's sends then come back
    /// `unregistered`.
    ///
    /// The relay's side is best effort, and skipped while the relay has asked
    /// to be left alone (C21). Either way the token stays valid there until
    /// this phone next registers for that server; without its key, nothing
    /// sent with it opens here for long.
    private func revoke(_ registration: RelayRegistration, droppingKey: Bool) async {
        if registration.serverBaseURL == configuration.baseURL, isSignedIn {
            try? await client.sendIgnoringResponse(
                "DELETE", "devices/push-token",
                body: ForgetPushTokenBody(relayToken: registration.relayToken)
            )
        }
        if relay.backoff.until == nil {
            do {
                try await RelayClient(baseURL: registration.relayURL, session: relay.session, attestor: relay.attestor)
                    .unregister(relayToken: registration.relayToken)
            } catch RelayClient.RelayError.rateLimited(let seconds) {
                relay.backoff.wait(seconds)
            } catch {}
        }
        if droppingKey {
            relay.keys.remove(for: registration.serverId)
        }
    }
}
