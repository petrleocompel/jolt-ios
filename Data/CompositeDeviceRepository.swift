import CoreBluetooth
import Foundation

/// Default `DeviceRepository`. Owns the one `BluetoothCentralManager` and
/// dispatches per-family operations to `LegacyDeviceController` /
/// `SCMaxDeviceController` — everything above this layer (`Features/`) is
/// unaware CoreBluetooth or ESF exist.
@MainActor
final class CompositeDeviceRepository: DeviceRepository {
    private let central = BluetoothCentralManager()
    private lazy var legacy = LegacyDeviceController(central: central)
    private lazy var scMax = SCMaxDeviceController(central: central)
    private lazy var deviceInfoReader = DeviceInformationReader(central: central)

    private var connectionStateContinuation: AsyncStream<DeviceConnectionState>.Continuation?
    private var connectedDeviceContinuation: AsyncStream<PavlokDevice?>.Continuation?

    private var connectedPeripheral: CBPeripheral?
    private var connectedFamily: DeviceFamily?

    private(set) lazy var connectionState: AsyncStream<DeviceConnectionState> = AsyncStream { continuation in
        self.connectionStateContinuation = continuation
    }

    private(set) lazy var connectedDevice: AsyncStream<PavlokDevice?> = AsyncStream { continuation in
        self.connectedDeviceContinuation = continuation
    }

    func startScan(for families: Set<DeviceFamily>) -> AsyncStream<PavlokDevice> {
        connectionStateContinuation?.yield(.scanning)
        let peripherals = central.startScan(serviceUUIDs: nil)
        return AsyncStream { continuation in
            let task = Task {
                for await peripheral in peripherals {
                    guard let name = peripheral.name,
                          let family = Self.family(matching: name, in: families) else { continue }
                    continuation.yield(PavlokDevice(peripheralIdentifier: peripheral.identifier, name: name, family: family))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func stopScan() {
        central.stopScan()
        connectionStateContinuation?.yield(.disconnected)
    }

    func connect(to device: PavlokDevice) async throws {
        connectionStateContinuation?.yield(.connecting)
        // Re-discovery is required: CoreBluetooth doesn't let us reconnect to
        // a CBPeripheral instance from a previous scan session by UUID alone
        // without `retrievePeripherals(withIdentifiers:)`, which needs the
        // central to already be powered on and have seen the identifier.
        guard central.isPoweredOn else {
            connectionStateContinuation?.yield(.failed("Bluetooth is off"))
            throw BluetoothCentralManager.BluetoothError.bluetoothUnavailable
        }
        let scan = central.startScan(serviceUUIDs: nil)
        var matched: CBPeripheral?
        for await peripheral in scan where peripheral.identifier == device.peripheralIdentifier {
            matched = peripheral
            break
        }
        central.stopScan()
        guard let peripheral = matched else {
            connectionStateContinuation?.yield(.failed("Device not found"))
            throw BluetoothCentralManager.BluetoothError.connectFailed(nil)
        }
        do {
            try await central.connect(peripheral)
            connectedPeripheral = peripheral
            connectedFamily = device.family
            connectionStateContinuation?.yield(.connected)
            connectedDeviceContinuation?.yield(device)
        } catch {
            connectionStateContinuation?.yield(.failed("\(error)"))
            throw error
        }
    }

    func disconnect() async {
        if let peripheral = connectedPeripheral {
            central.disconnect(peripheral)
        }
        connectedPeripheral = nil
        connectedFamily = nil
        connectionStateContinuation?.yield(.disconnected)
        connectedDeviceContinuation?.yield(nil)
    }

    func fire(_ stimulus: StimulusConfig) async throws {
        guard let peripheral = connectedPeripheral, let family = connectedFamily else {
            throw BluetoothCentralManager.BluetoothError.bluetoothUnavailable
        }
        switch family {
        case .pavlok2, .pavlok3:
            try await legacy.fire(stimulus, on: peripheral)
        case .shockClockMax:
            try await scMax.fire(stimulus, on: peripheral)
        }
    }

    func readDeviceInfo() async throws -> DeviceInfo {
        guard let peripheral = connectedPeripheral else {
            throw BluetoothCentralManager.BluetoothError.bluetoothUnavailable
        }
        return try await deviceInfoReader.read(from: peripheral)
    }

    func setButtonConfig(_ config: ButtonConfig, press: ButtonPressType) async throws {
        guard let peripheral = connectedPeripheral, let family = connectedFamily else {
            throw BluetoothCentralManager.BluetoothError.bluetoothUnavailable
        }
        switch family {
        case .pavlok2, .pavlok3:
            let payload = Data([press.wireValue, config.action.wireValue])
            try await central.write(payload, to: LegacyGATT.buttonConfig, serviceUUID: LegacyGATT.service, on: peripheral)
        case .shockClockMax:
            throw SCMaxDeviceController.ControllerError.notImplemented(
                "Button config opcode not recovered — see BLE/SCMax/ProtocolMap.swift"
            )
        }
    }

    func syncDeviceAlarm(_ alarm: Alarm) async throws {
        guard let peripheral = connectedPeripheral, let family = connectedFamily else {
            throw BluetoothCentralManager.BluetoothError.bluetoothUnavailable
        }
        switch family {
        case .pavlok2, .pavlok3:
            try await legacy.syncAlarm(alarm, on: peripheral)
        case .shockClockMax:
            try await scMax.syncAlarm(alarm, on: peripheral)
        }
    }

    func deleteDeviceAlarm(_ id: Alarm.ID) async throws {
        guard let peripheral = connectedPeripheral, let family = connectedFamily else {
            throw BluetoothCentralManager.BluetoothError.bluetoothUnavailable
        }
        switch family {
        case .pavlok2, .pavlok3:
            try await legacy.deleteAlarm(id, on: peripheral)
        case .shockClockMax:
            try await scMax.deleteAlarm(id, on: peripheral)
        }
    }

    private static func family(matching name: String, in families: Set<DeviceFamily>) -> DeviceFamily? {
        families.first { family in
            family.advertisedNamePrefixes.contains { name.localizedCaseInsensitiveContains($0) }
        }
    }
}

private extension ButtonPressType {
    /// Wire encoding unverified — see `LegacyDeviceController` header note.
    var wireValue: UInt8 {
        switch self {
        case .singlePress: return 0x01
        case .doublePress: return 0x02
        case .longPress: return 0x03
        }
    }
}

private extension ButtonAction {
    var wireValue: UInt8 {
        switch self {
        case .none: return 0x00
        case .fireStimulus: return 0x01
        case .toggleMute: return 0x02
        case .snoozeActiveAlarm: return 0x03
        }
    }
}
