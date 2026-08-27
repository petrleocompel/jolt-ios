import Foundation
import Observation

@MainActor
@Observable
final class PokeViewModel {
    private let repository: PokeRepository

    private(set) var activity: [PokeEvent] = []
    var lastError: String?

    @ObservationIgnored
    nonisolated(unsafe) private var activityTask: Task<Void, Never>?

    init(repository: PokeRepository) {
        self.repository = repository
        activityTask = Task { [weak self] in
            guard let self else { return }
            for await value in repository.activity { self.activity = value }
        }
    }

    deinit {
        activityTask?.cancel()
    }

    func send(to friend: Friend, stimulus: StimulusConfig) {
        lastError = nil
        Task { [weak self] in
            guard let self else { return }
            do {
                try await repository.sendPoke(to: friend.id, stimulus: stimulus)
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func simulateIncoming(from friend: Friend, stimulus: StimulusConfig) {
        Task { await repository.simulateIncomingPoke(from: friend.id, stimulus: stimulus) }
    }
}
