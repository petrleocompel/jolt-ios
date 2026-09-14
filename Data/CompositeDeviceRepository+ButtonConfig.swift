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
            guard let payload = config.action.payload(for: config.slot) else {
                throw ButtonConfigError.actionNotVerified(config.action)
            }
            try await central.write(
                payload,
                to: LegacyGATT.setupCharacteristic,
                serviceUUID: LegacyGATT.setupService,
                on: peripheral
            )
            // Read back rather than trusting the write. The setup
            // characteristic acknowledges anything, so a payload the firmware
            // doesn't understand looks exactly like success — the only honest
            // confirmation is what the device says it now holds. Logged, not
            // thrown on: the reply's own layout isn't decoded yet, so a
            // mismatch here isn't proof of failure.
            if let readback = try? await readRawButtonConfig() {
                BLELog.info("Button config readback: \(readback.map { String(format: "%02X", $0) }.joined(separator: " "))")
            }
        case .shockClockMax:
            throw SCMaxDeviceController.ControllerError.notImplemented(
                "Button config opcode not recovered — see BLE/SCMax/ProtocolMap.swift"
            )
        }
    }

    /// The setup characteristic's current contents, raw.
    ///
    /// `getDeviceButtonActions` reads the same `156E7000/7001` that
    /// `setButtonAction` writes, and the Android app parses the reply into
    /// `DeviceButtonConfigEntity`. That parse isn't recovered, so this returns
    /// bytes: a read is non-destructive (no stimulus can fire from one), and
    /// seeing what the device actually holds is the cheapest way to confirm a
    /// write landed and to pin down the reply layout.
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

private extension ButtonAction {
    /// The full `setButtonAction` payload for this action, or `nil` when its
    /// byte layout isn't recovered.
    ///
    /// Shape is `[0x02, buttonWire, actionWire, …tail]` — `0x02` is the
    /// command tag (the setup characteristic multiplexes `saveTimerToDevice`
    /// too), and the tail varies per action.
    ///
    /// - `disabled` → `[0x02, b, 0xFF]` — traced byte-for-byte
    /// - `toggleSleepTracking` → `[0x02, b, 0x13, 0x01, 0x02]` — traced
    /// - `findMyPhone` → `[0x02, b, 0x10]` — **tail assumed empty**, not
    ///   traced. It's written anyway because it's the one action worth the
    ///   risk and the risk is small: `findMyPhone` is a phone-side effect, so
    ///   the device can only announce it, never act on it — a wrong tail gets
    ///   a rejected write or an odd stored config, not a shock. The read-back
    ///   in `setButtonConfig` is how you see which.
    ///
    /// Everything else returns `nil` rather than a guess, because `zap` /
    /// `beep` / `vibrate` carry an intensity-shaped tail and a wrong guess
    /// there fires a real stimulus on the user's wrist.
    func payload(for slot: DeviceButtonSlot) -> Data? {
        let header: [UInt8] = [0x02, slot.wireValue]
        switch self {
        case .disabled:
            return Data(header + [0xFF])
        case .findMyPhone:
            return Data(header + [0x10])
        case .toggleSleepTracking:
            return Data(header + [0x13, 0x01, 0x02])
        case .stopWatch, .timer, .zap, .beep, .vibrate, .toggleCandle,
             .nextTune, .airplaneMode, .doNotDisturb, .defaultAction:
            return nil
        }
    }
}
