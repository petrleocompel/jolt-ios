import CoreBluetooth
import Foundation

// MARK: - Button config

/// `setButtonAction`'s real wire protocol, recovered by disassembling the
/// Android app's Dart AOT snapshot — see `docs/RE-FINDINGS.md` §3.
extension CompositeDeviceRepository {
    func setButtonConfig(_ config: ButtonConfig) async throws {
        let (peripheral, family) = try requireConnection()
        switch family {
        case .pavlok2, .pavlok3:
            // `setButtonAction` early-returns false for `backLong` in the Android app too.
            guard config.slot != .backLong else {
                throw ButtonConfigError.slotUnsupported(config.slot)
            }
            // Payload: `[0x02, DeviceButtonType.wire, DeviceButtonActionType.wire, …]` on
            // the setup characteristic. Only `.disabled` (no trailing bytes) is confirmed
            // against the decompiled Dart; other actions append unverified bytes and some
            // (zap/beep/vibrate) fire a real stimulus, so guessing isn't safe.
            guard config.action == .disabled else {
                throw ButtonConfigError.actionNotVerified(config.action)
            }
            let payload = Data([0x02, config.slot.wireValue, config.action.wireValue])
            try await central.write(
                payload,
                to: LegacyGATT.setupCharacteristic,
                serviceUUID: LegacyGATT.setupService,
                on: peripheral
            )
        case .shockClockMax:
            throw SCMaxDeviceController.ControllerError.notImplemented(
                "Button config opcode not recovered — see BLE/SCMax/ProtocolMap.swift"
            )
        }
    }
}

private extension DeviceButtonSlot {
    /// From `DeviceButtonType`'s object-pool dump — see docs/RE-FINDINGS.md §3.
    var wireValue: UInt8 {
        switch self {
        case .top: return 0x01
        case .middle: return 0x02
        case .bottom: return 0x03
        case .topLong: return 0x04
        case .middleLong: return 0x05
        case .bottomLong: return 0x06
        case .backLong: return 0x07
        }
    }
}

private extension ButtonAction {
    /// From `DeviceButtonActionType`'s object-pool dump — see
    /// docs/RE-FINDINGS.md §3. Only `.disabled` is ever actually written
    /// (`setButtonConfig` rejects everything else), so the other cases exist
    /// here purely for documentation completeness.
    var wireValue: UInt8 {
        switch self {
        case .findMyPhone: return 0x10
        case .stopWatch: return 0x01
        case .timer: return 0x02
        case .zap: return 0x03
        case .beep: return 0x02
        case .vibrate: return 0x01
        case .toggleCandle: return 0x06
        case .nextTune: return 0x07
        case .airplaneMode: return 0x08
        case .doNotDisturb: return 0x0d
        case .toggleSleepTracking: return 0x13
        case .disabled: return 0xff
        case .defaultAction: return 0xff  // real value is -1; never sent, so unverified
        }
    }
}
