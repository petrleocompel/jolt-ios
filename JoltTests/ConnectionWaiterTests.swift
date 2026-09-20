import XCTest
@testable import Jolt

/// The policy behind `CompositeDeviceRepository.fire`'s bounded wait for a
/// dropped link: a poke's silent push routinely wakes the app before
/// CoreBluetooth has reconnected, and failing instantly there reports a
/// wearable on the user's wrist as `deviceNotConnected`.
@MainActor
final class ConnectionWaiterTests: XCTestCase {
    /// The common case — connected already, so firing must not pay a single
    /// poll interval, let alone kick a redundant reconnect.
    func testReturnsImmediatelyWhenAlreadyConnected() async {
        let spy = WaiterSpy(connection: "link", isPaired: true)
        let waiter = spy.makeWaiter(budget: .seconds(4))

        let connection = await waiter.connection()

        XCTAssertEqual(connection, "link")
        XCTAssertEqual(spy.reconnectCount, 0)
        XCTAssertEqual(spy.sleepCount, 0)
    }

    /// The device-free paths (a quick poke with no wearable, a poke arriving
    /// on a phone that never paired one) must stay instant rather than stall
    /// for the whole budget waiting on a device that doesn't exist.
    func testGivesUpImmediatelyWhenNothingIsPaired() async {
        let spy = WaiterSpy(connection: nil, isPaired: false)
        let waiter = spy.makeWaiter(budget: .seconds(4))

        let connection = await waiter.connection()

        XCTAssertNil(connection)
        XCTAssertEqual(spy.reconnectCount, 0, "nothing to reconnect to")
        XCTAssertEqual(spy.sleepCount, 0)
    }

    /// The bug this whole seam exists for: paired, momentarily disconnected,
    /// and the link comes back inside the budget.
    func testWaitsForALinkThatComesBackWithinTheBudget() async {
        let spy = WaiterSpy(connection: nil, isPaired: true)
        // The reconnect the waiter kicks is what brings the link back, a few
        // polls later — as CoreBluetooth would.
        spy.onSleep = { [weak spy] count in
            if count == 3 { spy?.connection = "link" }
        }
        let waiter = spy.makeWaiter(budget: .seconds(4))

        let connection = await waiter.connection()

        XCTAssertEqual(connection, "link")
        XCTAssertEqual(spy.reconnectCount, 1)
        XCTAssertEqual(spy.sleepCount, 3, "should stop polling the moment the link is up")
    }

    func testStartsTheReconnectExactlyOnce() async {
        let spy = WaiterSpy(connection: nil, isPaired: true)
        let waiter = spy.makeWaiter(budget: .milliseconds(500))

        _ = await waiter.connection()

        XCTAssertEqual(spy.reconnectCount, 1, "one wait must not pile up reconnect attempts")
    }

    /// A link that never comes back gives up, and gives up *bounded* — the
    /// silent push handler can't afford an open-ended wait.
    func testGivesUpAfterTheBudgetIsSpent() async {
        let spy = WaiterSpy(connection: nil, isPaired: true)
        let waiter = spy.makeWaiter(budget: .milliseconds(500), pollInterval: .milliseconds(100))

        let connection = await waiter.connection()

        XCTAssertNil(connection)
        XCTAssertEqual(spy.sleepCount, 5, "budget / poll interval, then stop")
        XCTAssertEqual(spy.sleptFor.reduce(.zero, +), .milliseconds(500), "must not overrun its budget")
    }

    /// A budget shorter than one poll is still honoured rather than rounded
    /// up to a full interval.
    func testABudgetShorterThanOnePollStillEndsOnTime() async {
        let spy = WaiterSpy(connection: nil, isPaired: true)
        let waiter = spy.makeWaiter(budget: .milliseconds(30), pollInterval: .milliseconds(100))

        let connection = await waiter.connection()

        XCTAssertNil(connection)
        XCTAssertEqual(spy.sleptFor, [.milliseconds(30)])
    }

    func testAZeroBudgetChecksOnceAndGivesUp() async {
        let spy = WaiterSpy(connection: nil, isPaired: true)
        let waiter = spy.makeWaiter(budget: .zero)

        let connection = await waiter.connection()

        XCTAssertNil(connection)
        XCTAssertEqual(spy.sleepCount, 0)
        XCTAssertEqual(spy.reconnectCount, 1, "still worth kicking a reconnect for the next attempt")
    }

    /// iOS tearing down the background push handler mid-wait must end the
    /// wait, not spin through the rest of the budget.
    func testStopsWaitingWhenTheCallingTaskIsCancelled() async {
        let spy = WaiterSpy(connection: nil, isPaired: true)
        // A real sleep, so a cancelled wait that failed to notice would burn
        // the full ten seconds instead of the millisecond this takes.
        spy.sleepsForReal = true
        let waiter = spy.makeWaiter(budget: .seconds(10), pollInterval: .milliseconds(20))

        let task = Task { @MainActor in await waiter.connection() }
        task.cancel()
        let started = ContinuousClock.now
        let connection = await task.value

        XCTAssertNil(connection)
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(1))
        XCTAssertLessThanOrEqual(spy.sleepCount, 1, "must not spin through the remaining budget")
    }
}

/// Stands in for the repository's view of the link: what's connected, what's
/// paired, and what a reconnect does — none of which a test can get from a
/// real `CBCentralManager`.
@MainActor
private final class WaiterSpy {
    var connection: String?
    var isPaired: Bool
    private(set) var reconnectCount = 0
    private(set) var sleptFor: [Duration] = []
    var sleepCount: Int { sleptFor.count }

    /// Called with the running sleep count, so a test can bring the link up
    /// partway through the wait.
    var onSleep: ((Int) -> Void)?
    /// Off by default: the point of injecting the clock is that these tests
    /// take microseconds. The cancellation test needs a real suspension.
    var sleepsForReal = false

    init(connection: String?, isPaired: Bool) {
        self.connection = connection
        self.isPaired = isPaired
    }

    func makeWaiter(budget: Duration, pollInterval: Duration = .milliseconds(100)) -> ConnectionWaiter<String> {
        ConnectionWaiter<String>(
            budget: budget,
            pollInterval: pollInterval,
            isPaired: { [unowned self] in isPaired },
            currentConnection: { [unowned self] in connection },
            startReconnect: { [unowned self] in reconnectCount += 1 },
            sleep: { [unowned self] duration in
                sleptFor.append(duration)
                if sleepsForReal { try? await Task.sleep(for: duration) }
                onSleep?(sleptFor.count)
            }
        )
    }
}
