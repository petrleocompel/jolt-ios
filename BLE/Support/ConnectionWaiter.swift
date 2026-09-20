import Foundation

/// Bounded "give the link a moment to come back" policy, used by
/// `CompositeDeviceRepository.fire` before it reports a stimulus
/// undeliverable.
///
/// It exists as its own type mainly so the decision can be tested. The
/// repository it serves owns a real `CBCentralManager` and traffics in
/// `CBPeripheral`, which has no public initialiser — neither can be stood up
/// in a unit test. Nothing here mentions CoreBluetooth: `Connection` is
/// whatever the caller counts as "connected", and the clock is injected, so
/// the whole policy is exercisable in microseconds.
@MainActor
struct ConnectionWaiter<Connection> {
    /// Total time to wait for the link before giving up.
    let budget: Duration
    /// How long to leave between checks. The link coming back is signalled
    /// by CoreBluetooth on another path entirely; this just notices.
    let pollInterval: Duration

    /// The live connection, if there is one this instant.
    private let currentConnection: @MainActor () -> Connection?
    /// Whether there is a device to wait *for*. False means give up now:
    /// a phone that has never paired has nothing to reconnect to, and the
    /// device-free paths must stay instant rather than stall for the budget.
    private let isPaired: @MainActor () -> Bool
    /// Kicks off a reconnect attempt. Called at most once per wait, and only
    /// when paired but disconnected.
    private let startReconnect: @MainActor () -> Void
    /// Injected so tests don't spend real seconds waiting for a link that
    /// was never going to come back.
    private let sleep: @MainActor (Duration) async -> Void

    init(
        budget: Duration,
        pollInterval: Duration = .milliseconds(100),
        isPaired: @escaping @MainActor () -> Bool,
        currentConnection: @escaping @MainActor () -> Connection?,
        startReconnect: @escaping @MainActor () -> Void,
        sleep: @escaping @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.budget = budget
        self.pollInterval = pollInterval
        self.isPaired = isPaired
        self.currentConnection = currentConnection
        self.startReconnect = startReconnect
        self.sleep = sleep
    }

    /// The connection to use, or `nil` if the wait ran out — which the
    /// caller turns into whatever "no device" error it already threw.
    ///
    /// Returns immediately, without starting a reconnect, both when already
    /// connected and when nothing is paired. In between it counts the budget
    /// down in `pollInterval` steps rather than watching a wall clock, so an
    /// injected no-op sleep still terminates after a fixed number of checks
    /// instead of spinning.
    func connection() async -> Connection? {
        if let connection = currentConnection() { return connection }
        guard isPaired() else { return nil }
        startReconnect()

        var remaining = budget
        while remaining > .zero, !Task.isCancelled {
            let step = min(pollInterval, remaining)
            await sleep(step)
            if let connection = currentConnection() { return connection }
            remaining -= step
        }
        return nil
    }
}
