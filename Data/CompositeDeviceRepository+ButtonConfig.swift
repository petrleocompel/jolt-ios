import CoreBluetooth
import Foundation

// MARK: - Button config

/// `setButtonAction`'s real wire protocol, recovered from two independent
/// sources that agree byte for byte: the Android app's Dart AOT snapshot, and
/// the device firmware's own parser (`pavlok.bin` 6.8.0, `0x2F974`). See
/// `docs/RE-FINDINGS.md` §3.
extension CompositeDeviceRepository {
    func setButtonConfig(_ config: ButtonConfig) async throws {
        let (peripheral, family) = try requireConnection()
        switch family {
        case .pavlok2, .pavlok3:
            // The firmware validates the button byte as 1...6 and answers
            // anything else with an ATT error; `setButtonAction` in the
            // Android app early-returns for `backLong` for the same reason.
            guard config.slot != .backLong else {
                throw ButtonConfigError.slotUnsupported(config.slot)
            }
            guard let payload = config.action.payload(for: config.slot) else {
                throw ButtonConfigError.actionNotVerified(config.action)
            }
            // Write-with-response, and the error matters: the setup
            // characteristic requires write authorization, so the firmware
            // vets the payload and answers a bad one with ATT `0x0180`
            // instead of applying it. That rejection is the only signal that
            // a config didn't take — `BluetoothCentralManager.write` surfaces
            // it because `7001` advertises `.write`.
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

    /// The setup characteristic's current contents, raw.
    ///
    /// Note this is **not** the button config: the firmware's read-authorize
    /// handler answers a plain read of `7001` with a single status byte from
    /// its own state block, not with the stored actions. Reading the config
    /// back means writing the query command `01 01` and collecting the
    /// notifications the device then pushes on `7001` (what the Android app's
    /// `getDeviceButtonActions` does); that reply format isn't parsed yet.
    /// Kept because a read is harmless and the byte is still a live signal
    /// from the device.
    func readRawButtonConfig() async throws -> Data {
        let (peripheral, family) = try requireConnection()
        guard family != .shockClockMax else {
            throw SCMaxDeviceController.ControllerError.notImplemented(
                "Button config opcode not recovered — see BLE/SCMax/ProtocolMap.swift"
            )
        }
        return try await central.read(
            LegacyGATT.setupCharacteristic,
            from: LegacyGATT.setupService,
            on: peripheral
        )
    }
}

extension ButtonAction {
    /// The full `setButtonAction` payload for this action, or `nil` when its
    /// byte layout isn't recovered.
    ///
    /// Shape is `[0x02, buttonWire, actionWire, …tail]` — `0x02` is the
    /// command tag (the setup characteristic multiplexes a query command and
    /// `saveTimerToDevice` too), and the tail length is **fixed per action**.
    ///
    /// The length is the part that bites. The firmware looks the action byte
    /// up in a length table and rejects the write if fewer bytes follow
    /// (`0x2F3D8` → ATT `0x0180`), so `findMyPhone` written as three bytes
    /// instead of four is refused outright and the button keeps its old
    /// action — which is exactly why the device-triggered poke never fired.
    /// Lengths below are the firmware's own table, and the byte values match
    /// what the Android app writes:
    ///
    /// | action | payload | firmware length |
    /// |---|---|---|
    /// | `findMyPhone` | `10 00` | 2 |
    /// | `stopWatch` | `11 02 10 01` | 4 |
    /// | `timer` | `11 02 10 02` | 4 |
    /// | `toggleCandle` | `06` | 1 |
    /// | `nextTune` | `07` | 1 |
    /// | `toggleSleepTracking` | `13 01 02` | 3 (rejected by fw 6.8.0) |
    /// | `disabled` | `FF` | 1 |
    ///
    /// `zap` / `beep` / `vibrate` are left out on purpose: their payloads
    /// carry a count and an intensity (3 and 6 bytes), and writing one
    /// arms a real stimulus on the user's wrist. `airplaneMode` and
    /// `doNotDisturb` are out because the Android app doesn't write them
    /// either — its `setButtonAction` falls through to "unsupported" for
    /// both, so there is no traced payload to copy.
    /// Internal rather than private so the byte counts can be tested — the
    /// bug this replaced was a payload one byte short, which no amount of
    /// testing around it would have caught.
    func payload(for slot: DeviceButtonSlot) -> Data? {
        let header: [UInt8] = [0x02, slot.wireValue]
        switch self {
        case .findMyPhone:
            return Data(header + [0x10, 0x00])
        case .stopWatch:
            return Data(header + [0x11, 0x02, 0x10, 0x01])
        case .timer:
            return Data(header + [0x11, 0x02, 0x10, 0x02])
        case .toggleCandle:
            return Data(header + [0x06])
        case .nextTune:
            return Data(header + [0x07])
        case .toggleSleepTracking:
            return Data(header + [0x13, 0x01, 0x02])
        case .disabled:
            return Data(header + [0xFF])
        case .zap, .beep, .vibrate, .airplaneMode, .doNotDisturb, .defaultAction:
            return nil
        }
    }
}
