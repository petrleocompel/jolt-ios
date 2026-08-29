import Foundation

/// Fan-out for an `AsyncStream`-style signal so **more than one** feature can
/// observe it. A plain `AsyncStream` is single-consumer: a second `for await`
/// on the same stream steals events from the first. Once both the device UI
/// and the poke trigger needed to watch connection state, that bit — the
/// `DeviceControlViewModel` and `PokeTriggerService` were racing for the same
/// `connectedDevice` events, and whichever lost stayed blank (in snapshot mode
/// the app got stuck on onboarding).
///
/// Each `stream()` returns an independent subscription; new subscribers are
/// replayed the latest value so they don't have to wait for the next change to
/// learn the current state.
@MainActor
final class StreamHub<Element> {
    private var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]
    private var last: Element?
    private let replaysLast: Bool

    init(replaysLast: Bool = true) {
        self.replaysLast = replaysLast
    }

    func stream() -> AsyncStream<Element> {
        AsyncStream { continuation in
            let id = UUID()
            if replaysLast, let last {
                continuation.yield(last)
            }
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.continuations.removeValue(forKey: id) }
            }
        }
    }

    func yield(_ element: Element) {
        last = element
        for continuation in continuations.values {
            continuation.yield(element)
        }
    }
}
