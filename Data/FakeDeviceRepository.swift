import Foundation

/// Used only when `AppEnvironment.isSnapshotMode` is true, so App Store
/// screenshots show a connected device without needing real hardware in the
/// CI screenshot runner. See screenshot contract in
/// `~/.claude/skills/create-ios-app/screenshot-contract.md` /
/// `docs/RE-FINDINGS.md`.
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

    private var connectionStateContinuation: AsyncStream<DeviceConnectionState>.Continuation?
    private var connectedDeviceContinuation: AsyncStream<PavlokDevice?>.Continuation?

    private(set) lazy var connectionState: AsyncStream<DeviceConnectionState> = AsyncStream { continuation in
        self.connectionStateContinuation = continuation
        continuation.yield(.connected)
    }

    private(set) lazy var connectedDevice: AsyncStream<PavlokDevice?> = AsyncStream { continuation in
        self.connectedDeviceContinuation = continuation
        continuation.yield(self.fakeDevice)
    }

    func startScan(for families: Set<DeviceFamily>) -> AsyncStream<PavlokDevice> {
        AsyncStream { continuation in
            continuation.yield(self.fakeDevice)
            continuation.finish()
        }
    }

    func stopScan() {}

    func connect(to device: PavlokDevice) async throws {
        connectionStateContinuation?.yield(.connected)
        connectedDeviceContinuation?.yield(fakeDevice)
    }

    func disconnect() async {
        connectionStateContinuation?.yield(.disconnected)
        connectedDeviceContinuation?.yield(nil)
    }

    func forgetPairedDevice() async {
        connectionStateContinuation?.yield(.disconnected)
        connectedDeviceContinuation?.yield(nil)
    }

    func fire(_ stimulus: StimulusConfig) async throws {}

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

    func readDeviceInfo() async throws -> DeviceInfo { fakeDevice.info }

    func setButtonConfig(_ config: ButtonConfig, press: ButtonPressType) async throws {}

    func syncDeviceAlarm(_ alarm: Alarm) async throws {}

    func deleteDeviceAlarm(_ id: Alarm.ID) async throws {}
}
