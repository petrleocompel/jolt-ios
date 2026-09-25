import Foundation
import Observation

@MainActor
@Observable
final class PokeViewModel {
    private let repository: PokeRepository
    private let feedback: PokeFeedbackService?

    /// What kind of failure `lastError` describes. The three need different
    /// words, because only one of them means the friend definitely wasn't
    /// poked.
    enum SendFailure: Equatable {
        /// The server answered and said no — permission, cap, cooldown.
        case refused
        /// Never reached the server; confirmed against the activity feed.
        case notSent
        /// The answer was lost and the feed couldn't be checked: it may have
        /// landed. Retrying is safe either way.
        case unconfirmed
    }

    private(set) var activity: [PokeEvent] = []
    var lastError: String?
    /// True from tapping send until the server answers — the composer swaps
    /// its button for "Sending…" so a slow network can't be read as "nothing
    /// happened" and tapped again.
    private(set) var isSending = false
    private(set) var lastFailure: SendFailure?

    /// The poke Retry resends — including its id, which is what makes a retry
    /// the *same* poke to the server rather than a second one.
    private struct Attempt {
        let friend: Friend
        let stimulus: StimulusConfig
        let pokeID: UUID
    }

    @ObservationIgnored
    private var lastAttempt: Attempt?

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
        send(to: friend, stimulus: stimulus, pokeID: UUID())
    }

    /// Sends the last attempted poke again, under the same id — so if the
    /// first attempt did land after all, the server answers from its records
    /// and the friend is not poked twice.
    func retryLastSend() {
        guard let lastAttempt else { return }
        send(to: lastAttempt.friend, stimulus: lastAttempt.stimulus, pokeID: lastAttempt.pokeID)
    }

    func dismissError() {
        lastError = nil
        lastFailure = nil
    }

    private func send(to friend: Friend, stimulus: StimulusConfig, pokeID: UUID) {
        guard !isSending else { return }
        lastError = nil
        lastFailure = nil
        lastAttempt = Attempt(friend: friend, stimulus: stimulus, pokeID: pokeID)
        isSending = true
        Task { [weak self] in
            guard let self else { return }
            defer { isSending = false }
            do {
                try await repository.sendPoke(to: friend.id, stimulus: stimulus, pokeID: pokeID)
                feedback?.noteSuccess(
                    message: "Poked \(friend.displayName) · \(stimulus.kind.displayName) \(stimulus.intensity)%"
                )
            } catch {
                lastFailure = Self.failure(for: error)
                lastError = error.localizedDescription
            }
        }
    }

    private static func failure(for error: Error) -> SendFailure {
        switch error {
        case PokeSendError.notSent:
            return .notSent
        case PokeSendError.unconfirmed:
            return .unconfirmed
        // A dropped connection the repository didn't get to check: it may
        // have landed, so it must not be reported as "not sent".
        case JoltAPIClient.APIError.transport, is URLError:
            return .unconfirmed
        default:
            return .refused
        }
    }

    func simulateIncoming(from friend: Friend, stimulus: StimulusConfig) {
        Task { await repository.simulateIncomingPoke(from: friend.id, stimulus: stimulus) }
    }
}
