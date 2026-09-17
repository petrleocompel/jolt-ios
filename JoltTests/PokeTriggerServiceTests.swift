import XCTest
@testable import Jolt

/// Runtime behaviour of the trigger — the parts `PokeTriggerTests` can't
/// cover, because they're about *when* the service is listening rather than
/// what a `PokeTrigger` matches.
@MainActor
final class PokeTriggerServiceTests: XCTestCase {
    private let eventsChar = "156E2002-A300-4FEA-897B-86F698D74461"

    private func makeService(
        device: StubDeviceRepository,
        poke: SpyPokeRepository
    ) -> PokeTriggerService {
        let defaults = UserDefaults(suiteName: "PokeTriggerServiceTests-\(UUID().uuidString)")!
        let service = PokeTriggerService(
            deviceRepository: device,
            pokeRepository: poke,
            store: PokeTriggerStore(defaults: defaults),
            retryDelay: .milliseconds(20)
        )
        service.setEnabled(true)
        service.setTarget(friendID: UUID(), name: "Test Friend")
        service.setButtonSlot(.topLong)
        return service
    }

    /// The failure that made this look dead in the field: the event feed threw
    /// once (a connect race is enough), and because the finished task was left
    /// in place nothing could ever start it again — no error state, no retry,
    /// a trigger that reports itself configured and never fires.
    func testEventFeedIsReopenedAfterAFailure() async throws {
        let device = StubDeviceRepository()
        let poke = SpyPokeRepository()
        device.failuresBeforeSuccess = 1
        let service = makeService(device: device, poke: poke)

        service.start()
        device.connect()
        try await waitUntil { service.isListening }

        device.emit(DeviceEvent(serviceUUID: "s", characteristicUUID: eventsChar, data: Data([0x0C, 0x01, 0x00])))
        try await waitUntil { poke.sentCount == 1 }
        XCTAssertGreaterThanOrEqual(device.eventStreamRequests, 2)
    }

    /// A dropped connection ends the feed without an error; reconnecting has
    /// to bring it back.
    func testEventFeedResumesAfterAReconnect() async throws {
        let device = StubDeviceRepository()
        let poke = SpyPokeRepository()
        let service = makeService(device: device, poke: poke)

        service.start()
        device.connect()
        try await waitUntil { service.isListening }

        device.dropConnection()
        try await waitUntil { !service.isListening }
        device.connect()
        try await waitUntil { service.isListening }

        device.emit(DeviceEvent(serviceUUID: "s", characteristicUUID: eventsChar, data: Data([0x0C, 0x01, 0x00])))
        try await waitUntil { poke.sentCount == 1 }
    }

    func testOnlyTheConfiguredButtonFires() async throws {
        let device = StubDeviceRepository()
        let poke = SpyPokeRepository()
        let service = makeService(device: device, poke: poke)

        service.start()
        device.connect()
        try await waitUntil { service.isListening }

        // Another device event on the events characteristic, and a
        // find-my-phone-shaped frame from a different characteristic.
        device.emit(DeviceEvent(serviceUUID: "s", characteristicUUID: eventsChar, data: Data([0x04, 0x01, 0x00])))
        device.emit(DeviceEvent(serviceUUID: "s", characteristicUUID: "0000200A-0000-1000-8000-00805F9B34FB",
                                data: Data([0x0C, 0x01, 0x00])))
        try await waitUntil { service.recentEvents.count == 2 }
        XCTAssertEqual(poke.sentCount, 0)
    }

    func testMakeButtonReportPressesWritesFindMyPhoneToTheChosenButton() async {
        let device = StubDeviceRepository()
        let service = makeService(device: device, poke: SpyPokeRepository())

        await service.makeButtonReportPresses()

        XCTAssertEqual(device.writtenButtonConfigs, [ButtonConfig(slot: .topLong, action: .findMyPhone)])
        XCTAssertNotNil(service.lastButtonConfigNote)
        XCTAssertNil(service.lastError)
    }

    /// A rejected write must not read as success. The firmware refuses a
    /// payload it doesn't accept (the setup characteristic is
    /// write-authorized), and the whole point of surfacing that is to stop the
    /// user pressing a button that was never reconfigured.
    func testMakeButtonReportPressesSurfacesARejectedWrite() async {
        let device = StubDeviceRepository()
        device.failButtonConfigWrite = true
        let service = makeService(device: device, poke: SpyPokeRepository())

        await service.makeButtonReportPresses()

        XCTAssertNil(service.lastButtonConfigNote)
        XCTAssertNotNil(service.lastError)
    }

    // MARK: Helpers

    /// Polls `condition` rather than sleeping a fixed amount — the work here
    /// hops between tasks, so a fixed wait is either flaky or slow.
    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Condition not met within \(timeout)", file: file, line: line)
    }
}

// MARK: - Doubles

@MainActor
private final class SpyPokeRepository: PokeRepository {
    private(set) var sentCount = 0

    var activity: AsyncStream<[PokeEvent]> { AsyncStream { $0.finish() } }

    func sendPoke(to friendID: Friend.ID, stimulus: StimulusConfig) async throws {
        sentCount += 1
    }

    @discardableResult
    func handleIncomingPoke(_ payload: PokePushPayload) async -> PokeDeliveryStatus { .deviceNotConnected }
    func simulateIncomingPoke(from friendID: Friend.ID, stimulus: StimulusConfig) async {}
}

private enum StubError: Error { case notReady }

/// A `DeviceRepository` whose connection state and event feed the test drives
/// directly.
@MainActor
private final class StubDeviceRepository: DeviceRepository {
    /// How many times `deviceEventStream()` throws before it starts working.
    var failuresBeforeSuccess = 0
    private(set) var eventStreamRequests = 0
    private(set) var writtenButtonConfigs: [ButtonConfig] = []

    private let connectionHub = StreamHub<PavlokDevice?>()
    private var eventContinuation: AsyncStream<DeviceEvent>.Continuation?

    func connect() { connectionHub.yield(PavlokDevice(peripheralIdentifier: UUID(), name: "Stub", family: .pavlok3)) }

    func dropConnection() {
        eventContinuation?.finish()
        eventContinuation = nil
        connectionHub.yield(nil)
    }

    func emit(_ event: DeviceEvent) { eventContinuation?.yield(event) }

    var connectionState: AsyncStream<DeviceConnectionState> { AsyncStream { $0.finish() } }
    var connectedDevice: AsyncStream<PavlokDevice?> { connectionHub.stream() }
    let hasPairedDevice = true
    let pairedDeviceName: String? = "Stub"
    func reconnect() async {}

    func deviceEventStream() async throws -> AsyncStream<DeviceEvent> {
        eventStreamRequests += 1
        if failuresBeforeSuccess > 0 {
            failuresBeforeSuccess -= 1
            throw StubError.notReady
        }
        return AsyncStream { continuation in
            self.eventContinuation = continuation
        }
    }

    /// Makes `setButtonConfig` throw, standing in for the device refusing the
    /// write.
    var failButtonConfigWrite = false

    func setButtonConfig(_ config: ButtonConfig) async throws {
        if failButtonConfigWrite { throw StubError.notReady }
        writtenButtonConfigs.append(config)
    }

    func readRawButtonConfig() async throws -> Data { Data([0x02, 0x04, 0x10]) }

    // Unused surface.
    func startScan(for families: Set<DeviceFamily>) -> AsyncStream<PavlokDevice> { AsyncStream { $0.finish() } }
    func stopScan() {}
    func connect(to device: PavlokDevice) async throws {}
    func disconnect() async {}
    func forgetPairedDevice() async {}
    func fire(_ stimulus: StimulusConfig) async throws {}
    func readDeviceInfo() async throws -> DeviceInfo { DeviceInfo() }
    func syncDeviceAlarm(_ alarm: Alarm) async throws {}
    func deleteDeviceAlarm(_ id: Alarm.ID) async throws {}
    private(set) var stimulusSettings: StimulusSettings = .default
    @discardableResult
    func saveStimulusConfig(_ config: StimulusConfig) async -> StimulusSyncState { .localOnly(reason: "unused") }
    func dumpGATT(readingValues: Bool) async throws -> [GATTCharacteristicDump] { [] }
    func writeRaw(_ data: Data, characteristicUUID: String, serviceUUID: String, mode: RawWriteMode) async throws {}
    @discardableResult
    func startListeningForDeviceEvents() async throws -> Int { 0 }
    func stopListeningForDeviceEvents() {}
}
