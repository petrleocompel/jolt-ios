import XCTest
@testable import Jolt

/// The dashboard's battery readout used to be whatever the wearable happened
/// to say at connect time, for the whole session: it was read exactly once,
/// and the refreshes on the detail and diagnostics screens kept what they
/// read to themselves.
///
/// These pin the contract that fixes both halves — every path that learns a
/// new battery level republishes the connected device, so the card and the
/// screens stacked on top of it cannot disagree.
@MainActor
final class DeviceBatteryRefreshTests: XCTestCase {
    /// A device that notifies (0x2A19 declares `notify`, as every Pavlok
    /// seen so far does): the level moves on the wearable and subscribers
    /// hear about it with nothing asking.
    func testABatteryChangeOnTheWearableReachesSubscribers() async throws {
        let repository = FakeDeviceRepository()
        let dashboard = DeviceObserver(repository)
        try await waitUntil { dashboard.battery == 82 }

        repository.simulateBatteryLevel(63)

        try await waitUntil { dashboard.battery == 63 }
    }

    /// A device that can't notify: the hardware has moved but nothing is
    /// published until the poll — or the foreground refresh, or a
    /// pull-to-refresh — asks. Until then subscribers are entitled to the
    /// stale value; afterwards they are not.
    func testASilentBatteryChangeIsPublishedByTheNextRead() async throws {
        let repository = FakeDeviceRepository()
        let dashboard = DeviceObserver(repository)
        try await waitUntil { dashboard.battery == 82 }

        repository.simulateBatteryLevel(41, notifying: false)
        let read = try await repository.readDeviceInfo()

        XCTAssertEqual(read.batteryLevelPercent, 41)
        try await waitUntil { dashboard.battery == 41 }
    }

    /// The regression this file exists for: the detail screen reads, shows a
    /// current percentage, and the dashboard card behind it keeps the old
    /// one. Both observe the same stream, so one refreshing has to move the
    /// other.
    func testARefreshOnOneScreenMovesEveryOtherObserver() async throws {
        let repository = FakeDeviceRepository()
        // The dashboard card's subscription, taken before the detail screen
        // exists — as it is in the app.
        let dashboard = DeviceObserver(repository)
        try await waitUntil { dashboard.battery == 82 }

        repository.simulateBatteryLevel(27, notifying: false)
        // The detail screen's `load()`.
        let detail = try await repository.readDeviceInfo()

        try await waitUntil { dashboard.battery == detail.batteryLevelPercent }
    }

    /// A refresh has nothing to publish when the wearable is gone — it must
    /// not put a device back on a stream that has just been told there
    /// isn't one.
    func testAReadWithNothingConnectedPublishesNothing() async throws {
        let repository = FakeDeviceRepository()
        let dashboard = DeviceObserver(repository)
        try await waitUntil { dashboard.battery == 82 }
        await repository.disconnect()
        try await waitUntil { dashboard.published.last == .some(nil) }

        _ = try await repository.readDeviceInfo()

        XCTAssertEqual(dashboard.published.last, .some(nil))
    }

    /// Reconnecting republishes the level the wearable has *now*, not the one
    /// it had when the link dropped.
    func testReconnectingPublishesTheCurrentLevel() async throws {
        let repository = FakeDeviceRepository()
        let dashboard = DeviceObserver(repository)
        await repository.disconnect()

        repository.simulateBatteryLevel(55, notifying: false)
        await repository.reconnect()

        try await waitUntil { dashboard.battery == 55 }
    }

    /// Stands in for the dashboard card: subscribes once and keeps every
    /// device it is handed, the way `DeviceControlViewModel` does.
    @MainActor
    private final class DeviceObserver {
        private(set) var published: [PavlokDevice?] = []
        // `nonisolated(unsafe)` so the always-nonisolated `deinit` can cancel it.
        nonisolated(unsafe) private var task: Task<Void, Never>?

        init(_ repository: DeviceRepository) {
            task = Task { [weak self] in
                for await device in repository.connectedDevice {
                    self?.published.append(device)
                }
            }
        }

        deinit { task?.cancel() }

        /// What this observer currently believes the battery to be.
        var battery: Int? { published.last??.info.batteryLevelPercent }
    }

    /// The streams publish through detached `Task`s, so there's no completion
    /// to await — poll instead, with a ceiling so a value that never arrives
    /// fails the test rather than hanging the suite on `next()` forever.
    private func waitUntil(
        timeout: Duration = .seconds(3),
        _ condition: () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Condition not met within \(timeout)", file: file, line: line)
    }
}
