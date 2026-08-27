import Foundation

@MainActor
protocol PokeRepository {
    var activity: AsyncStream<[PokeEvent]> { get }
    func sendPoke(to friendID: Friend.ID, stimulus: StimulusConfig) async throws

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
}
