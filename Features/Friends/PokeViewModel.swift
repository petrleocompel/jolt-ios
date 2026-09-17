import Foundation
import Observation

@MainActor
@Observable
final class PokeViewModel {
    private let repository: PokeRepository
    private let feedback: PokeFeedbackService?

    private(set) var activity: [PokeEvent] = []
    var lastError: String?
    /// True from tapping send until the server answers — the composer swaps
    /// its button for "Sending…" so a slow network can't be read as "nothing
    /// happened" and tapped again.
    private(set) var isSending = false
    /// Whether `lastError` came from failing to reach the server at all, as
    /// opposed to the server refusing the poke.
    private(set) var lastErrorIsConnectivity = false

    @ObservationIgnored
    private var lastAttempt: (friend: Friend, stimulus: StimulusConfig)?

    @ObservationIgnored
    nonisolated(unsafe) private var activityTask: Task<Void, Never>?

    init(repository: PokeRepository, feedback: PokeFeedbackService? = nil) {
        self.repository = repository
        self.feedback = feedback
        activityTask = Task { [weak self] in
            guard let self else { return }
            for await value in repository.activity { self.activity = value }
        }
    }

    deinit {
        activityTask?.cancel()
    }

    func send(to friend: Friend, stimulus: StimulusConfig) {
        guard !isSending else { return }
        lastError = nil
        lastErrorIsConnectivity = false
        lastAttempt = (friend, stimulus)
        isSending = true
        Task { [weak self] in
            guard let self else { return }
            defer { isSending = false }
            do {
                try await repository.sendPoke(to: friend.id, stimulus: stimulus)
                feedback?.noteSuccess(
                    message: "Poked \(friend.displayName) · \(stimulus.kind.displayName) \(stimulus.intensity)%"
                )
            } catch {
                if case JoltAPIClient.APIError.transport = error {
                    lastErrorIsConnectivity = true
                } else {
                    lastErrorIsConnectivity = error is URLError
                }
                lastError = error.localizedDescription
            }
        }
    }

    /// Sends the last attempted poke again, unchanged.
    func retryLastSend() {
        guard let lastAttempt else { return }
        send(to: lastAttempt.friend, stimulus: lastAttempt.stimulus)
    }

    func dismissError() {
        lastError = nil
        lastErrorIsConnectivity = false
    }

    func simulateIncoming(from friend: Friend, stimulus: StimulusConfig) {
        Task { await repository.simulateIncomingPoke(from: friend.id, stimulus: stimulus) }
    }
}
