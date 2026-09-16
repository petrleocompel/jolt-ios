import Foundation

/// Stand-in wearable for runs with no hardware: App Store screenshots show a
/// connected device without needing one (see the screenshot contract in
/// `~/.claude/skills/create-ios-app/screenshot-contract.md` /
/// `docs/RE-FINDINGS.md`), and UI tests reach the tab bar. Selected by
/// `AppEnvironment.usesFakeDevice`; `startsPaired` picks which side of the
/// device/no-device split to simulate.
@MainActor
final class FakeDeviceRepository: DeviceRepository {
    private let fakeDevice = PavlokDevice(
        peripheralIdentifier: UUID(),
        name: "pavlok-3",
        family: .pavlok3,
        info: DeviceInfo(
            modelNumber: "Pavlok 3",
            serialNumber: "DEMO-0001",
            firmwareRevision: "1.4.2",
            hardwareRevision: "B",
            softwareRevision: "1.4.2",
            manufacturer: "Pavlok Inc.",
            batteryLevelPercent: 82
        ),
        lastConnectedAt: .now
    )

    // Multi-consumer (device UI + poke trigger), seeded so every subscriber —
    // whichever starts first — sees the same starting state.
    private let connectionStateHub = StreamHub<DeviceConnectionState>()
    private let connectedDeviceHub = StreamHub<PavlokDevice?>()

    private(set) var hasPairedDevice: Bool

    /// - Parameter startsPaired: pass `false` (see
    ///   `AppEnvironment.startsWithoutDevice`) for a launch that has never
    ///   paired a wearable — the state a new user is in before, or instead
    ///   of, buying one. Lets the device-free path be exercised hermetically
    ///   rather than only on hardware.
    init(startsPaired: Bool = true) {
        self.hasPairedDevice = startsPaired
        connectionStateHub.yield(startsPaired ? .connected : .disconnected)
        connectedDeviceHub.yield(startsPaired ? fakeDevice : nil)
    }

    var connectionState: AsyncStream<DeviceConnectionState> { connectionStateHub.stream() }
    var connectedDevice: AsyncStream<PavlokDevice?> { connectedDeviceHub.stream() }

    func startScan(for families: Set<DeviceFamily>) -> AsyncStream<PavlokDevice> {
        AsyncStream { continuation in
            continuation.yield(self.fakeDevice)
            continuation.finish()
        }
    }

    func stopScan() {}

    func connect(to device: PavlokDevice) async throws {
        hasPairedDevice = true
        connectionStateHub.yield(.connected)
        connectedDeviceHub.yield(fakeDevice)
    }

    /// Disconnecting keeps the pairing, matching `CompositeDeviceRepository`.
    func disconnect() async {
        connectionStateHub.yield(.disconnected)
        connectedDeviceHub.yield(nil)
    }

    func forgetPairedDevice() async {
        hasPairedDevice = false
        connectionStateHub.yield(.disconnected)
        connectedDeviceHub.yield(nil)
    }

    /// Throws when nothing is connected rather than silently succeeding, so
    /// an incoming poke with no wearable around lands on
    /// `PokeDeliveryStatus.deviceNotConnected` here exactly as it would on
    /// real hardware.
    func fire(_ stimulus: StimulusConfig) async throws {
        guard hasPairedDevice else { throw FakeDeviceError.notConnected }
    }

    private(set) var stimulusSettings: StimulusSettings = .default

    @discardableResult
    func saveStimulusConfig(_ config: StimulusConfig) async -> StimulusSyncState {
        stimulusSettings[config.kind] = config
        return .syncedToDevice
    }

    /// A plausible-looking table so the diagnostics screenshot has content.
    func dumpGATT(readingValues: Bool) async throws -> [GATTCharacteristicDump] {
        [
            GATTCharacteristicDump(serviceUUID: "180A", uuid: "2A24", properties: ["read"]),
            GATTCharacteristicDump(serviceUUID: "180A", uuid: "2A26", properties: ["read"]),
            GATTCharacteristicDump(serviceUUID: "180F", uuid: "2A19", properties: ["read", "notify"]),
            GATTCharacteristicDump(serviceUUID: "156E1000-A300-4FEA-897B-86F698D74461", uuid: "1001", properties: ["read", "write"]),
            GATTCharacteristicDump(serviceUUID: "156E1000-A300-4FEA-897B-86F698D74461", uuid: "1002", properties: ["read", "write"]),
            GATTCharacteristicDump(serviceUUID: "156E1000-A300-4FEA-897B-86F698D74461", uuid: "1003", properties: ["read", "write"])
        ]
    }

    func writeRaw(_ data: Data, characteristicUUID: String, serviceUUID: String) async throws {}

    @discardableResult
    func startListeningForDeviceEvents() async throws -> Int { 0 }

    func stopListeningForDeviceEvents() {}

    func deviceEventStream() async throws -> AsyncStream<DeviceEvent> {
        AsyncStream { $0.finish() }
    }

    func readDeviceInfo() async throws -> DeviceInfo { fakeDevice.info }

    func setButtonConfig(_ config: ButtonConfig) async throws {}

    func readRawButtonConfig() async throws -> Data { Data([0x02, 0x01, 0xFF]) }

    func syncDeviceAlarm(_ alarm: Alarm) async throws {}

    func deleteDeviceAlarm(_ id: Alarm.ID) async throws {}

    enum FakeDeviceError: LocalizedError {
        case notConnected

        var errorDescription: String? { "No device connected." }
    }
}
