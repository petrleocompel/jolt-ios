import Foundation

/// Stand-in wearable for runs with no hardware: App Store screenshots show a
/// connected device without needing one (see the screenshot contract in
/// `~/.claude/skills/create-ios-app/screenshot-contract.md` /
/// `docs/RE-FINDINGS.md`), and UI tests reach the tab bar. Selected by
/// `AppEnvironment.usesFakeDevice`; `startsPaired` picks which side of the
/// device/no-device split to simulate.
@MainActor
final class FakeDeviceRepository: DeviceRepository {
    private var fakeDevice = PavlokDevice(
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
        lastConnectedAt: .now,
        rssi: -54
    )

    // Multi-consumer (device UI + poke trigger), seeded so every subscriber —
    // whichever starts first — sees the same starting state.
    private let connectionStateHub = StreamHub<DeviceConnectionState>()
    private let connectedDeviceHub = StreamHub<PavlokDevice?>()

    private(set) var hasPairedDevice: Bool

    var pairedDeviceName: String? { hasPairedDevice ? fakeDevice.name : nil }

    func reconnect() async {
        guard hasPairedDevice else { return }
        connectionStateHub.yield(.connected)
        connectedDeviceHub.yield(fakeDevice)
    }

    /// - Parameter startsPaired: pass `false` (see
    ///   `AppEnvironment.startsWithoutDevice`) for a launch that has never
    ///   paired a wearable — the state a new user is in before, or instead
    ///   of, buying one. Lets the device-free path be exercised hermetically
    ///   rather than only on hardware.
    /// - Parameter unreachableState: with `startsPaired`, start paired but
    ///   *not* connected, in this state (`.disconnected` = out of range,
    ///   `.connecting`, `.failed`) — see `AppEnvironment.fakeDeviceLinkState`.
    init(startsPaired: Bool = true, unreachableState: DeviceConnectionState? = nil) {
        self.hasPairedDevice = startsPaired
        if startsPaired, let unreachableState {
            connectionStateHub.yield(unreachableState)
            connectedDeviceHub.yield(nil)
        } else {
            connectionStateHub.yield(startsPaired ? .connected : .disconnected)
            connectedDeviceHub.yield(startsPaired ? fakeDevice : nil)
        }
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

    /// Every raw write, in order, so tests can assert what the Protocol lab
    /// actually asked for — including the write type, which is otherwise
    /// invisible without hardware.
    private(set) var rawWrites: [RawWrite] = []

    struct RawWrite {
        let data: Data
        let characteristicUUID: String
        let serviceUUID: String
        let mode: RawWriteMode
    }

    func writeRaw(_ data: Data, characteristicUUID: String, serviceUUID: String, mode: RawWriteMode) async throws {
        guard hasPairedDevice else { throw FakeDeviceError.notConnected }
        rawWrites.append(RawWrite(data: data, characteristicUUID: characteristicUUID, serviceUUID: serviceUUID, mode: mode))
    }

    @discardableResult
    func startListeningForDeviceEvents() async throws -> Int { 0 }

    func stopListeningForDeviceEvents() {}

    func deviceEventStream() async throws -> AsyncStream<DeviceEvent> {
        AsyncStream { $0.finish() }
    }

    /// Publishes as well as returns, exactly as `CompositeDeviceRepository`
    /// does — a refresh on one screen is how every other one finds out.
    func readDeviceInfo() async throws -> DeviceInfo {
        if isConnected { connectedDeviceHub.yield(fakeDevice) }
        return fakeDevice.info
    }

    /// Moves the stand-in wearable's battery the way the hardware would.
    ///
    /// - Parameter notifying: `true` models a device whose 0x2A19 notifies —
    ///   the new level reaches subscribers by itself. `false` models one
    ///   that has to be asked (the poll / foreground-refresh path): the
    ///   hardware has moved but nothing is published until something calls
    ///   `readDeviceInfo()`.
    func simulateBatteryLevel(_ percent: Int, notifying: Bool = true) {
        fakeDevice.info.batteryLevelPercent = percent
        guard notifying, isConnected else { return }
        connectedDeviceHub.yield(fakeDevice)
    }

    /// What subscribers currently believe, which is not the same question as
    /// `hasPairedDevice` — a paired wearable can be out of range.
    private var isConnected: Bool { (connectedDeviceHub.latest ?? nil) != nil }

    func setButtonConfig(_ config: ButtonConfig) async throws {}

    func readButtonConfig() async throws -> ButtonConfigReport {
        // A plausible two-button report: top is left at the firmware's
        // vibrate default, top-long has been set to findMyPhone.
        ButtonConfigReport.parse(frames: [
            Data([0xE1, 0x01, 0x01]), Data([0x01, 0x01, 0x02, 0x50, 0x16, 0x16]),
            Data([0xE1, 0x04, 0x01]), Data([0x10, 0x00])
        ])
    }

    func readRawButtonConfig() async throws -> Data { Data([0x02, 0x01, 0xFF]) }

    func syncDeviceAlarm(_ alarm: Alarm) async throws {}

    func deleteDeviceAlarm(_ id: Alarm.ID) async throws {}

    enum FakeDeviceError: LocalizedError {
        case notConnected

        var errorDescription: String? { "No device connected." }
    }
}
