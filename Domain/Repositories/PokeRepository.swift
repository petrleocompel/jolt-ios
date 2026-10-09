import Foundation

@MainActor
protocol PokeRepository {
    var activity: AsyncStream<[PokeEvent]> { get }

    /// Sends one poke. `pokeID` names it: sending the same id again is a retry
    /// of the same poke, never a second one — which is what makes Retry safe
    /// after a connection that dropped before the answer came back.
    func sendPoke(to friendID: Friend.ID, stimulus: StimulusConfig, pokeID: UUID) async throws

    /// The one real "a poke arrived" code path — fires the stimulus (if the
    /// device is connected and permission allows it) and logs a
    /// `PokeEvent`. Called identically by `JoltAppDelegate` for a real (or
    /// `simctl push`-simulated) APNs push and by the in-app "simulate
    /// incoming poke" debug affordance, so both exercise the same logic.
    @discardableResult
    func handleIncomingPoke(_ payload: PokePushPayload) async -> PokeDeliveryStatus

    /// UI convenience: builds a `PokePushPayload` from a known friend and
    /// runs it through `handleIncomingPoke`.
    func simulateIncomingPoke(from friendID: Friend.ID, stimulus: StimulusConfig) async

    /// A push's `userInfo` as the poke and test parsers should read it:
    /// decrypted if it came through the relay, as it came otherwise. Nil
    /// when it must be dropped instead — sealed for another server, failing
    /// to open, or arriving in plaintext where only sealed pushes are
    /// expected. Called by every notification path before anything else.
    func openIncomingPush(_ userInfo: [AnyHashable: Any]) -> [AnyHashable: Any]?
}

extension PokeRepository {
    /// For a backend that never registers through the relay: a relayed push
    /// can't be meant for it.
    func openIncomingPush(_ userInfo: [AnyHashable: Any]) -> [AnyHashable: Any]? {
        RelayedPush.isRelayed(userInfo) ? nil : userInfo
    }

    /// A new poke, for callers that never retry it themselves.
    func sendPoke(to friendID: Friend.ID, stimulus: StimulusConfig) async throws {
        try await sendPoke(to: friendID, stimulus: stimulus, pokeID: UUID())
    }
}

/// Why a poke might not have gone out, told apart because "the connection
/// dropped" alone says nothing about whether the poke arrived — the request
/// may well have reached the server before the answer was lost.
enum PokeSendError: LocalizedError, Equatable {
    /// The connection dropped, and the activity feed confirms the server never
    /// recorded it.
    case notSent
    /// The connection dropped and the feed could not be checked either. It may
    /// have landed; retrying is safe, because the same poke can't land twice.
    case unconfirmed

    var errorDescription: String? {
        switch self {
        case .notSent:
            return "The connection dropped before the server got it — nothing was sent."
        case .unconfirmed:
            return "The connection dropped before the server answered, so it isn't clear "
                + "the poke arrived. Retrying is safe: it can't be delivered twice."
        }
    }
}
