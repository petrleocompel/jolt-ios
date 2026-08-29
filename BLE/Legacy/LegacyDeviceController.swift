import CoreBluetooth
import Foundation

/// Talks to Pavlok 2/3 over `LegacyGATT`.
///
/// The wire format below is decompiled, not guessed: blutter
/// (OWASP MASTG-TOOL-0116) against the Android app's Dart AOT snapshot gives
/// `BleManager::performZap` / `performMotor` / `performPiezo` and their
/// `update*` counterparts in full.
///
/// All three outputs are characteristics of the config service, and firing
/// and configuring are *the same write* — they differ only in a flag added
/// to the first byte:
///
///     performZap   → add 0x80      updateZap   → add 0x40
///     performMotor → add 0x80      updateMotor → add 0x40
///     performPiezo → add 0x80      updatePiezo → add 0x40
///
/// That is why every earlier write was acknowledged and did nothing: the
/// first byte was copied back from the device with neither bit set, so the
/// device was told to neither fire nor store.
///
/// Payloads, cross-checked against a live Pavlok 3 (fw 6.10.0):
///
///     zap   1003  [count|flag, level]                              2 bytes
///     vibe  1001  [count|flag, 0x0C, level, onInterval, offInterval] 5 bytes
///     beep  1002  [count|flag, 0x0C, level, onInterval, offInterval] 5 bytes
///
/// The device read back `01 0C 23 16 16` on `1001`, `01 0C 64 16 16` on
/// `1002` and `01 19` on `1003` — count 1; the constant `0x0C` that
/// `performMotor` writes literally; vibration 35, beep 100, zap 25; and the
/// two encoded interval bytes. Every field lines up.
struct LegacyDeviceController {
    enum ControllerError: LocalizedError {
        case unknownLayout(String, Int)

        var errorDescription: String? {
            switch self {
            case .unknownLayout(let uuid, let length):
                return "\(uuid) returned \(length) bytes, which doesn't match any known Pavlok layout. Nothing was written."
            }
        }
    }

    /// The flag added to byte 0. Fire and store are otherwise identical.
    enum Command: UInt8 {
        /// `perform*` — fire immediately.
        case fire = 0x80
        /// `update*` — store as the device-side default.
        case store = 0x40
    }

    private let central: BluetoothCentralManager
    private let protocolStore: LegacyProtocolStore

    init(central: BluetoothCentralManager, protocolStore: LegacyProtocolStore = LegacyProtocolStore()) {
        self.central = central
        self.protocolStore = protocolStore
    }

    /// Builds the payload from the device's current value.
    ///
    /// Count and level are overwritten; the constant at index 1 and the two
    /// encoded interval bytes are carried through from `existing` rather than
    /// recomputed. `MotorConfig.encodedOnInterval` / `encodedOffInterval`
    /// derive those from millisecond fields this app doesn't expose, so
    /// preserving whatever the device already has keeps the user's pattern
    /// intact instead of flattening it to a default.
    ///
    /// Count is masked to 6 bits so it can never carry into the command flag.
    static func payload(for stimulus: StimulusConfig, existing: Data, command: Command) -> Data? {
        let level = UInt8(clamping: stimulus.intensity)
        let count = UInt8(clamping: stimulus.repetitions) & 0x3F
        let first = count | command.rawValue

        var bytes = [UInt8](existing)
        switch bytes.count {
        case 2:
            return Data([first, level])
        case 5:
            bytes[0] = first
            bytes[2] = level
            return Data(bytes)
        default:
            return nil
        }
    }

    private func write(_ stimulus: StimulusConfig, command: Command, on peripheral: CBPeripheral) async throws {
        let characteristic = protocolStore.characteristic(for: stimulus.kind)
        let existing = try await central.read(
            characteristic,
            from: LegacyGATT.service,
            on: peripheral,
            timeout: .seconds(3)
        )
        guard let payload = Self.payload(for: stimulus, existing: existing, command: command) else {
            BLELog.error("Unrecognised \(existing.count)-byte layout at \(characteristic.uuidString) — refusing to write")
            throw ControllerError.unknownLayout(characteristic.uuidString, existing.count)
        }
        BLELog.info(
            "\(command == .fire ? "Fire" : "Store") \(stimulus.kind.rawValue) "
                + "intensity=\(stimulus.intensity) reps=\(stimulus.repetitions) → \(characteristic.uuidString)"
        )
        try await central.write(payload, to: characteristic, serviceUUID: LegacyGATT.service, on: peripheral)
    }

    func fire(_ stimulus: StimulusConfig, on peripheral: CBPeripheral) async throws {
        try await write(stimulus, command: .fire, on: peripheral)
    }

    /// Stores `stimulus` as the device-side default, so the physical button
    /// and on-device alarms use it.
    func saveStimulusConfig(_ stimulus: StimulusConfig, on peripheral: CBPeripheral) async throws {
        try await write(stimulus, command: .store, on: peripheral)
    }

    /// Alarm slot *bytes* go to `kApplicationDownloadCharcUuid` (`5002`),
    /// per `BleManager::writeAlarmBytesToDevice`. Commands about an alarm
    /// (read, snooze, turn off) go to `kApplicationControlCharcUuid`
    /// (`5001`) instead, and the device reports alarm state by notifying
    /// `kApplicationAlarmNotifyCharcUuid` (`5003`).
    ///
    /// The target is now confirmed; the payload below is still a guess.
    func syncAlarm(_ alarm: Alarm, on peripheral: CBPeripheral) async throws {
        var dayBitmask: UInt8 = 0
        for day in alarm.repeatDays {
            dayBitmask |= 1 << UInt8(day.rawValue - 1)
        }
        let payload = Data([
            UInt8(alarm.hour),
            UInt8(alarm.minute),
            dayBitmask,
            alarm.isEnabled ? 1 : 0
        ]) + Data(alarm.id.uuidBytes.prefix(4))
        try await central.write(
            payload,
            to: LegacyGATT.applicationDownload,
            serviceUUID: LegacyGATT.applicationService,
            on: peripheral
        )
    }

    /// Deleting is a command rather than a slot write, so it goes to the
    /// control point. Payload unverified.
    func deleteAlarm(_ id: Alarm.ID, on peripheral: CBPeripheral) async throws {
        let payload = Data([0xFF]) + Data(id.uuidBytes.prefix(4))
        try await central.write(
            payload,
            to: LegacyGATT.applicationControl,
            serviceUUID: LegacyGATT.applicationService,
            on: peripheral
        )
    }
}

private extension UUID {
    var uuidBytes: [UInt8] {
        withUnsafeBytes(of: uuid) { Array($0) }
    }
}
