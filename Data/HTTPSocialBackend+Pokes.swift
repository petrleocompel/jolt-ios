import Foundation

/// Sending, receiving and acking pokes against a real Jolt Server. Kept out of
/// `HTTPSocialBackend.swift` so neither file grows past readable size — the
/// same split as `HTTPSocialBackend+PushDiagnostics.swift`.
///
/// This is the half that can actuate hardware, so it is also where the app
/// decides *not* to: a poke names its addressee, and one meant for another
/// account is dropped rather than fired.
extension HTTPSocialBackend {
    fileprivate struct SendPokeBody: Encodable {
        let friendId: String
        let stimulus: StimulusConfig
        /// Makes a resend of the same poke a retry the server answers from
        /// its records, rather than a second poke.
        let pokeId: String
    }

    fileprivate struct AckBody: Encodable {
        let status: PokeDeliveryStatus
    }

    func sendPoke(to friendID: Friend.ID, stimulus: StimulusConfig, pokeID: UUID) async throws {
        let body = SendPokeBody(friendId: friendID.apiString, stimulus: stimulus, pokeId: pokeID.apiString)
        do {
            let _: PokeEvent = try await BackgroundActivity.run("Send poke") {
                try await send("POST", "pokes", body: body)
            }
        } catch JoltAPIClient.APIError.transport {
            // The connection dropped — most often the screen locking right
            // after the tap. The request may well have arrived before the
            // answer was lost, so ask the feed instead of guessing: reporting
            // "not sent" for a poke that landed is what used to invite a
            // second one.
            switch await isRecorded(pokeID) {
            case true?: break
            case false?: throw PokeSendError.notSent
            case nil: throw PokeSendError.unconfirmed
            }
        }
        await refreshActivity()
    }

    /// Whether the server holds a poke with this id. Nil when it can't be
    /// asked either — still offline, most likely.
    private func isRecorded(_ pokeID: UUID) async -> Bool? {
        guard let events: [PokeEvent] = try? await send("GET", "pokes") else { return nil }
        return events.contains { $0.id == pokeID }
    }

    @discardableResult
    func handleIncomingPoke(_ payload: PokePushPayload) async -> PokeDeliveryStatus {
        // Addressed to somebody else. Only possible when this device is still
        // registered to an account it is no longer signed in as, and the one
        // outcome worth preventing: firing here would shock whoever is
        // holding this phone for a poke they were never sent. Re-assert the
        // registration so the next one goes to the right place.
        //
        // Deliberately narrow: only a payload that *names* a different
        // addressee is dropped. No handle (older server) or no known account
        // (a silent push that woke the app before the session restored) means
        // "can't tell", which must never be read as "not mine".
        if let addressee = payload.recipientHandle, !myHandle.isEmpty, addressee != myHandle {
            print("[Jolt] dropped a poke addressed to @\(addressee) — signed in as @\(myHandle)")
            await registerLastPushToken()
            return .notAllowed
        }

        // `firer` guards against the same poke arriving via both a background
        // silent push and a subsequent notification tap — never fires twice.
        let status = await firer.fire(id: payload.pokeID, stimulus: payload.stimulus)
        // Tell the server what actually happened. Idempotent server-side, so
        // an alert push and a silent push for the same poke are both safe to
        // ack.
        do {
            // A silent push wakes the app for seconds at most; without asking
            // for more, iOS can freeze it halfway through telling the sender
            // what happened.
            try await BackgroundActivity.run("Ack poke") {
                try await sendIgnoringResponse(
                    "POST", "pokes/\(payload.pokeID.apiString)/ack",
                    body: AckBody(status: status)
                )
            }
        } catch JoltAPIClient.APIError.server(404, _) {
            // The server only accepts an ack from the poke's recipient, so a
            // 404 means this device fired something addressed to another
            // account — the same stale registration as above, caught on a
            // server too old to say so in the payload.
            print("[Jolt] server rejected the ack for \(payload.pokeID.apiString) — this poke was not ours")
            await registerLastPushToken()
        } catch {
            // Any other failure costs the sender their delivery status and
            // nothing else.
        }
        await refreshActivity()
        return status
    }

    func simulateIncomingPoke(from friendID: Friend.ID, stimulus: StimulusConfig) async {
        guard let friend = friendsList.first(where: { $0.id == friendID }) else { return }
        await handleIncomingPoke(PokePushPayload(
            pokeID: UUID(),
            senderHandle: friend.handle,
            senderDisplayName: friend.displayName,
            recipientHandle: myHandle,
            stimulus: stimulus
        ))
    }
}
