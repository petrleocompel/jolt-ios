import XCTest
@testable import Jolt

/// Retry has to stay available after a dropped connection — and has to be
/// safe when the first attempt landed after all. It is safe only because it
/// resends the *same* poke id, which the server answers from its records.
@MainActor
final class PokeViewModelRetryTests: XCTestCase {
    private let friend = Friend(
        id: UUID(), handle: "alice", displayName: "Alice",
        permissionsGrantedToMe: .none, permissionsIGranted: .none
    )
    private let stimulus = StimulusConfig(kind: .zap, intensity: 30, repetitions: 1)

    func testRetryResendsTheSamePokeID() async throws {
        let repository = RecordingPokeRepository(failures: [PokeSendError.unconfirmed])
        let viewModel = PokeViewModel(repository: repository)

        viewModel.send(to: friend, stimulus: stimulus)
        try await waitUntil { !viewModel.isSending }
        XCTAssertEqual(viewModel.lastFailure, .unconfirmed)

        viewModel.retryLastSend()
        try await waitUntil { !viewModel.isSending && repository.sentIDs.count == 2 }

        XCTAssertEqual(repository.sentIDs[0], repository.sentIDs[1], "a retry must be the same poke, not a new one")
        XCTAssertNil(viewModel.lastFailure)
    }

    func testANewSendIsANewPoke() async throws {
        let repository = RecordingPokeRepository(failures: [])
        let viewModel = PokeViewModel(repository: repository)

        viewModel.send(to: friend, stimulus: stimulus)
        try await waitUntil { !viewModel.isSending && repository.sentIDs.count == 1 }
        viewModel.send(to: friend, stimulus: stimulus)
        try await waitUntil { !viewModel.isSending && repository.sentIDs.count == 2 }

        XCTAssertNotEqual(repository.sentIDs[0], repository.sentIDs[1])
    }

    /// A refusal (cooldown, cap) is not a connectivity problem, and a transport
    /// error nobody verified may have landed — neither is "not sent".
    func testClassifiesFailuresByWhatTheyMeanForTheFriend() async throws {
        for (error, expected) in [
            (PokeSendError.notSent as Error, PokeViewModel.SendFailure.notSent),
            (JoltAPIClient.APIError.transport("gone"), .unconfirmed),
            (JoltAPIClient.APIError.server(status: 403, message: "Too soon"), .refused),
        ] {
            let repository = RecordingPokeRepository(failures: [error])
            let viewModel = PokeViewModel(repository: repository)
            viewModel.send(to: friend, stimulus: stimulus)
            try await waitUntil { !viewModel.isSending && repository.sentIDs.count == 1 }
            XCTAssertEqual(viewModel.lastFailure, expected, "\(error)")
        }
    }

    private func waitUntil(timeout: Duration = .seconds(2), _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else { return XCTFail("condition not met in time") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

@MainActor
private final class RecordingPokeRepository: PokeRepository {
    private var failures: [Error]
    private(set) var sentIDs: [UUID] = []

    init(failures: [Error]) { self.failures = failures }

    var activity: AsyncStream<[PokeEvent]> { AsyncStream { $0.finish() } }

    func sendPoke(to friendID: Friend.ID, stimulus: StimulusConfig, pokeID: UUID) async throws {
        sentIDs.append(pokeID)
        if !failures.isEmpty { throw failures.removeFirst() }
    }

    @discardableResult
    func handleIncomingPoke(_ payload: PokePushPayload) async -> PokeDeliveryStatus { .fired }
    func simulateIncomingPoke(from friendID: Friend.ID, stimulus: StimulusConfig) async {}
}
