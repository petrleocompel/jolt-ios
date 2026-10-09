import Foundation

/// Taking a relay registration back. Kept out of
/// `HTTPSocialBackend+PushRegistration.swift` so neither file grows past
/// readable size.
///
/// The relay's side of a revocation is only done once the relay says so: until
/// then it can still push with the token, so the token is kept as pending and
/// retried rather than forgotten.
extension HTTPSocialBackend {
    /// Asks the relay again to revoke the tokens it hasn't confirmed revoking,
    /// unless it has asked to be left alone for now. Whatever is still
    /// pending afterwards is tried again once that wait is over.
    func retryPendingRelayUnregistrations() async {
        for pending in relay.registrations.pendingUnregistrations() {
            guard relay.backoff.until == nil else { break }
            do {
                try await RelayClient(baseURL: pending.relayURL, session: relay.session, attestor: relay.attestor)
                    .unregister(relayToken: pending.relayToken)
                relay.registrations.removePendingUnregistration(relayToken: pending.relayToken)
            } catch RelayClient.RelayError.rateLimited(let seconds) {
                relay.backoff.wait(seconds)
                break
            } catch {
                // Unreachable, most likely. The rest would fail the same way.
                break
            }
        }
        scheduleRelayUnregistrationRetry()
    }

    /// One retry at a time: when the relay's wait ends, or in a minute if it
    /// was simply out of reach. Launch, sign-in and every registration try
    /// again too.
    private func scheduleRelayUnregistrationRetry() {
        guard pendingUnregistrationRetry == nil, !relay.registrations.pendingUnregistrations().isEmpty else { return }
        let delay = max(1, relay.backoff.until?.timeIntervalSinceNow ?? RelayClient.defaultRetryAfter)
        pendingUnregistrationRetry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled else { return }
            self.pendingUnregistrationRetry = nil
            await self.retryPendingRelayUnregistrations()
        }
    }

    /// Revokes the stored relay registration everywhere it can, and forgets
    /// it and its key.
    func retireRelayRegistration() async {
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
    /// The relay's side is kept as pending until the relay confirms it, and
    /// retried — not dropped — when the relay asks to wait (C21) or can't be
    /// reached: forgetting the token would leave the relay able to push to a
    /// phone that no longer treats its pushes as relayed.
    func revoke(_ registration: RelayRegistration, droppingKey: Bool) async {
        if registration.serverBaseURL == configuration.baseURL, isSignedIn {
            try? await client.sendIgnoringResponse(
                "DELETE", "devices/push-token",
                body: ForgetPushTokenBody(relayToken: registration.relayToken)
            )
        }
        relay.registrations.addPendingUnregistration(registration)
        if droppingKey {
            relay.keys.remove(for: registration.serverId)
        }
        await retryPendingRelayUnregistrations()
    }

    /// A token the relay issued that never became the registration — its key
    /// couldn't be stored. Revoked like any other, through the pending list.
    func abandon(_ registration: RelayRegistration) async {
        relay.registrations.addPendingUnregistration(registration)
        await retryPendingRelayUnregistrations()
    }
}
