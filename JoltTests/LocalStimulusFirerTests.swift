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
        fireCount += 1
    }

    func readDeviceInfo() async throws -> DeviceInfo { DeviceInfo() }
    func setButtonConfig(_ config: ButtonConfig) async throws {}
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
