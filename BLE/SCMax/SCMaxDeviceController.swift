import CoreBluetooth
import Foundation

/// Talks to Shock Clock Max. Standard GATT reads (battery, device info) work
/// today. Anything that requires an ESF message over the control point
/// (`fire(_:)`, alarms, triggers, hand-detect) throws `.notImplemented` until
/// `ProtocolMap.swift` is filled in from a real capture.
struct SCMaxDeviceController: DeviceController {
    enum ControllerError: LocalizedError {
        case notImplemented(String)

        var errorDescription: String? {
            switch self {
            case .notImplemented(let detail): return detail
            }
        }
    }

    private let central: BluetoothCentralManager

    init(central: BluetoothCentralManager) {
        self.central = central
    }

    func fire(_ stimulus: StimulusConfig, on peripheral: CBPeripheral) async throws {
        guard SCMaxProtocolMap.fireStimulusOpcode != nil else {
            throw ControllerError.notImplemented(
                "Shock Clock Max stimulus opcode not recovered — see BLE/SCMax/ProtocolMap.swift"
            )
        }
        // Once the opcode is known:
        //   let message = ESFValue.map(["op": .int(...), "kind": ..., "intensity": ...])
        //   try await central.write(Data(ESFCodec.encode(message)), to: SCMaxGATT.controlPointWrite,
        //                            serviceUUID: SCMaxGATT.controlPointsService, on: peripheral)
    }

    /// Same blocker as `fire(_:on:)` — the ESF opcode for writing a
    /// device-side stimulus default is not recovered. The phone-side value is
    /// still saved by `CompositeDeviceRepository`, which reports
    /// `.localOnly` when this throws.
    func saveStimulusConfig(_ stimulus: StimulusConfig, on peripheral: CBPeripheral) async throws {
        throw ControllerError.notImplemented(
            "Shock Clock Max stimulus config opcode not recovered — see BLE/SCMax/ProtocolMap.swift"
        )
    }

    func syncAlarm(_ alarm: Alarm, on peripheral: CBPeripheral) async throws {
        throw ControllerError.notImplemented(
            "Shock Clock Max alarm opcode not recovered — see BLE/SCMax/ProtocolMap.swift"
        )
    }

    func deleteAlarm(_ id: Alarm.ID, on peripheral: CBPeripheral) async throws {
        throw ControllerError.notImplemented(
            "Shock Clock Max alarm opcode not recovered — see BLE/SCMax/ProtocolMap.swift"
        )
    }
}
