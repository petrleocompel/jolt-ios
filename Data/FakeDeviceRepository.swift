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

    func readDeviceInfo() async throws -> DeviceInfo { fakeDevice.info }

    func setButtonConfig(_ config: ButtonConfig, press: ButtonPressType) async throws {}

    func syncDeviceAlarm(_ alarm: Alarm) async throws {}

    func deleteDeviceAlarm(_ id: Alarm.ID) async throws {}
}
