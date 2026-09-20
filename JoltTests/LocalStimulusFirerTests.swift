import XCTest
@testable import Jolt

@MainActor
final class LocalStimulusFirerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: PokeSettings.doNotDisturbKey)
    }

    func testFiresOnceForAGivenID() async {
        let device = CountingDeviceRepository()
        let firer = LocalStimulusFirer(deviceRepository: device)
        let id = UUID()
        let stimulus = StimulusConfig(kind: .zap, intensity: 20, repetitions: 1)

        let first = await firer.fire(id: id, stimulus: stimulus)
        let second = await firer.fire(id: id, stimulus: stimulus)

        XCTAssertEqual(first, .fired)
        XCTAssertEqual(second, .fired)
        XCTAssertEqual(device.fireCount, 1, "a second call with the same id must not fire again")
    }

    func testDifferentIDsEachFire() async {
        let device = CountingDeviceRepository()
        let firer = LocalStimulusFirer(deviceRepository: device)
        let stimulus = StimulusConfig(kind: .zap, intensity: 20, repetitions: 1)

        _ = await firer.fire(id: UUID(), stimulus: stimulus)
        _ = await firer.fire(id: UUID(), stimulus: stimulus)

        XCTAssertEqual(device.fireCount, 2)
    }

    /// The reported bug: the silent background push wakes the app before
    /// CoreBluetooth has restored the link, so its attempt fails — and the
    /// alert the user then taps, with the wearable plainly connected, must
    /// still fire rather than replay the cached failure.
    func testRetriesAfterAnAttemptThatFoundNoDevice() async {
        let device = CountingDeviceRepository()
        device.isConnected = false
        let firer = LocalStimulusFirer(deviceRepository: device)
        let id = UUID()
        let stimulus = StimulusConfig(kind: .zap, intensity: 20, repetitions: 1)

        let background = await firer.fire(id: id, stimulus: stimulus)
        XCTAssertEqual(background, .deviceNotConnected)
        XCTAssertEqual(device.fireCount, 0)

        device.isConnected = true
        let tap = await firer.fire(id: id, stimulus: stimulus)

        XCTAssertEqual(tap, .fired, "a failed attempt must not poison the next delivery path")
        XCTAssertEqual(device.fireCount, 1)
    }

    /// ...but once it has actually fired, the retry window closes again.
    func testDoesNotFireAgainAfterAFailureThenASuccess() async {
        let device = CountingDeviceRepository()
        device.isConnected = false
        let firer = LocalStimulusFirer(deviceRepository: device)
        let id = UUID()
        let stimulus = StimulusConfig(kind: .zap, intensity: 20, repetitions: 1)

        _ = await firer.fire(id: id, stimulus: stimulus)
        device.isConnected = true
        _ = await firer.fire(id: id, stimulus: stimulus)
        let third = await firer.fire(id: id, stimulus: stimulus)

        XCTAssertEqual(third, .fired)
        XCTAssertEqual(device.fireCount, 1)
    }

    /// Both pushes landing at once still means one shock: the second call
    /// joins the in-flight attempt instead of starting its own.
    func testConcurrentCallsForTheSameIDFireOnce() async {
        let device = CountingDeviceRepository()
        device.fireDelay = .milliseconds(50)
        let firer = LocalStimulusFirer(deviceRepository: device)
        let id = UUID()
        let stimulus = StimulusConfig(kind: .zap, intensity: 20, repetitions: 1)

        async let first = firer.fire(id: id, stimulus: stimulus)
        async let second = firer.fire(id: id, stimulus: stimulus)
        let results = await [first, second]

        XCTAssertEqual(results, [.fired, .fired])
        XCTAssertEqual(device.fireCount, 1, "two pushes arriving together must not shock twice")
    }

    /// DND is a decision, not a failure — a muted poke stays muted even if
    /// the user turns DND off before the second delivery path arrives.
    func testMutedPokeIsNotRetried() async {
        UserDefaults.standard.set(true, forKey: PokeSettings.doNotDisturbKey)
        defer { UserDefaults.standard.removeObject(forKey: PokeSettings.doNotDisturbKey) }

        let device = CountingDeviceRepository()
        let firer = LocalStimulusFirer(deviceRepository: device)
        let id = UUID()
        let stimulus = StimulusConfig(kind: .zap, intensity: 20, repetitions: 1)

        let muted = await firer.fire(id: id, stimulus: stimulus)
        XCTAssertEqual(muted, .muted)
        UserDefaults.standard.set(false, forKey: PokeSettings.doNotDisturbKey)

        let afterDNDOff = await firer.fire(id: id, stimulus: stimulus)
        XCTAssertEqual(afterDNDOff, .muted)
        XCTAssertEqual(device.fireCount, 0)
    }

    func testRespectsDoNotDisturbWithoutFiring() async {
        UserDefaults.standard.set(true, forKey: PokeSettings.doNotDisturbKey)
        defer { UserDefaults.standard.removeObject(forKey: PokeSettings.doNotDisturbKey) }

        let device = CountingDeviceRepository()
        let firer = LocalStimulusFirer(deviceRepository: device)
        let status = await firer.fire(id: UUID(), stimulus: StimulusConfig(kind: .zap, intensity: 20, repetitions: 1))

        XCTAssertEqual(status, .muted)
        XCTAssertEqual(device.fireCount, 0)
    }
}

/// Minimal `DeviceRepository` spy — only `fire` is exercised by these tests,
/// everything else is an unused stub.
@MainActor
private final class CountingDeviceRepository: DeviceRepository {
    private(set) var fireCount = 0
    /// Flipped mid-test to play the wearable coming back within the app's
    /// lifetime — the situation the silent-push retry exists for.
    var isConnected = true
    /// Holds `fire` open long enough for a second call to race into it.
    var fireDelay: Duration?

    enum StubError: Error { case notConnected }

    var connectionState: AsyncStream<DeviceConnectionState> { AsyncStream { $0.finish() } }
    var connectedDevice: AsyncStream<PavlokDevice?> { AsyncStream { $0.finish() } }
    let hasPairedDevice = true
    let pairedDeviceName: String? = "Stub"
    func reconnect() async {}

    func startScan(for families: Set<DeviceFamily>) -> AsyncStream<PavlokDevice> { AsyncStream { $0.finish() } }
    func stopScan() {}
    func connect(to device: PavlokDevice) async throws {}
    func disconnect() async {}
    func forgetPairedDevice() async {}

    func fire(_ stimulus: StimulusConfig) async throws {
        if let fireDelay { try? await Task.sleep(for: fireDelay) }
        guard isConnected else { throw StubError.notConnected }
        fireCount += 1
    }

    func readDeviceInfo() async throws -> DeviceInfo { DeviceInfo() }
    func setButtonConfig(_ config: ButtonConfig) async throws {}
    func readButtonConfig() async throws -> ButtonConfigReport { ButtonConfigReport() }
    func readRawButtonConfig() async throws -> Data { Data() }
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
    func deviceEventStream() async throws -> AsyncStream<DeviceEvent> { AsyncStream { $0.finish() } }
}
