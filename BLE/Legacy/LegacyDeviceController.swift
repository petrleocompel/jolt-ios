import CoreBluetooth
import Foundation

/// Talks to Pavlok 2/3 over `LegacyGATT`.
///
/// ## The config service stores settings; it does not fire
///
/// Read off a real Pavlok 3 (fw 6.10.0), `156E1000` holds eight structs:
///
///     1001  01 0C 23 16 16            1005  05 01 00 29 06 08 26 08
///     1002  01 0C 64 16 16            1006  06 70 02 1E
///     1003  01 19                     1007  03 00 00 00
///     1004  01 00 00 00 29            1008  00 02 00 00 00 00 00 00
///
/// `1001` and `1002` are identical except at index 2 — `0x23` (35) against
/// `0x64` (100) — which is a zap at 35% and a motor at 100%. That is the
/// intensity byte, and `1003`'s `01 19` is the same idea two bytes wide.
///
/// Writing them is acknowledged and produces nothing audible. Index 1 was
/// briefly set to `0x14` (20) by an earlier version of this file: if that
/// field were a pulse count, twenty pulses would have been felt. Nothing
/// was. So a config write configures, exactly as the Android binary's split
/// between `updateDeviceZap` and `performDeviceZap` implies.
///
/// ## Triggering is not recovered
///
/// The command that actually fires is somewhere else — most likely the
/// application service's write-only control points (`2002`, `2009`), which
/// hold no readable value to inspect. `fire(_:on:)` therefore sets the
/// intensity and then throws, rather than reporting success for something
/// that produced no sensation.
///
/// The way to close this without an HCI capture is
/// `Diagnostics → Listen for device events`: subscribe to every notifying
/// characteristic, press the button on the Pavlok, and read what the device
/// says about a stimulus it fired itself.
struct LegacyDeviceController {
    enum ControllerError: LocalizedError {
        case unknownLayout(String, Int)
        case triggerNotRecovered

        var errorDescription: String? {
            switch self {
            case .unknownLayout(let uuid, let length):
                return "\(uuid) holds \(length) bytes in a layout this app doesn't know. Nothing was written."
            case .triggerNotRecovered:
                return "Intensity saved to the device, but the command that actually fires a stimulus "
                    + "hasn't been recovered yet. Use Diagnostics → Listen for device events and press "
                    + "the button on your Pavlok to capture it."
            }
        }
    }

    private let central: BluetoothCentralManager
    private let protocolStore: LegacyProtocolStore

    init(central: BluetoothCentralManager, protocolStore: LegacyProtocolStore = LegacyProtocolStore()) {
        self.central = central
        self.protocolStore = protocolStore
    }

    /// Where the intensity byte sits, by characteristic length.
    ///
    /// Read off a real Pavlok 3 (fw 6.10.0). `1001` and `1002` are
    /// byte-for-byte identical except at index 2:
    ///
    ///     1001 zap       01 0C 23 16 16      0x23 =  35
    ///     1002 vibration 01 0C 64 16 16      0x64 = 100
    ///     1003 piezo     01 19               0x19 =  25
    ///
    /// A zap defaulting to 35% and a motor to 100% is exactly the shape you
    /// would expect, and nothing else in the struct differs — so index 2 is
    /// the level. Index 1 is a bounded field shared by both (it holds `0x0C`
    /// on each, accepted `0x05` and `0x14`, and rejected `0x32` outright).
    /// An earlier version wrote the level *there*, which corrupted a field it
    /// did not understand and never set the intensity at all.
    static func levelOffset(forLength length: Int) -> Int? {
        switch length {
        case 2: return 1
        case 5: return 2
        default: return nil
        }
    }

    /// Rewrites only the intensity byte, leaving every other byte exactly as
    /// the device reported it.
    ///
    /// Deliberately minimal: the remaining fields are not understood, and on
    /// this firmware an out-of-range value in one of them is rejected with a
    /// bare ATT error. Preserving them means the write either sets the
    /// intensity or changes nothing.
    ///
    /// Returns nil when the length is unrecognised — better to refuse than to
    /// scribble on an unknown struct.
    static func payload(for stimulus: StimulusConfig, existing: Data?) -> Data? {
        guard let existing, let offset = levelOffset(forLength: existing.count) else { return nil }
        var bytes = existing
        bytes[bytes.startIndex + offset] = UInt8(clamping: stimulus.intensity)
        return bytes
    }

    /// Writes the intensity into the kind's config characteristic.
    ///
    /// This *configures*; it does not fire. See the type header — a write
    /// here is acknowledged and silent, which is what configuring looks like.
    private func writeConfig(_ stimulus: StimulusConfig, on peripheral: CBPeripheral) async throws {
        let characteristic = protocolStore.characteristic(for: stimulus.kind)
        let existing = try await central.read(
            characteristic,
            from: LegacyGATT.service,
            on: peripheral,
            timeout: .seconds(3)
        )
        let hex = existing.map { String(format: "%02X", $0) }.joined(separator: " ")
        BLELog.info("\(characteristic.uuidString) currently holds \(existing.count) byte(s): \(hex)")

        guard let payload = Self.payload(for: stimulus, existing: existing) else {
            BLELog.error("Unrecognised \(existing.count)-byte layout for \(characteristic.uuidString) — refusing to write")
            throw ControllerError.unknownLayout(characteristic.uuidString, existing.count)
        }
        BLELog.info("Set \(stimulus.kind.rawValue) intensity=\(stimulus.intensity) → \(characteristic.uuidString)")
        try await central.write(payload, to: characteristic, serviceUUID: LegacyGATT.service, on: peripheral)
    }

    /// Sets the intensity, then reports that triggering is not yet known.
    ///
    /// The config write is still worth doing — it is the half that works, and
    /// it is what the physical button and on-device alarms use. Throwing
    /// afterwards keeps the UI honest instead of showing "sent" for something
    /// that produced no sensation.
    func fire(_ stimulus: StimulusConfig, on peripheral: CBPeripheral) async throws {
        try await writeConfig(stimulus, on: peripheral)
        throw ControllerError.triggerNotRecovered
    }

    func saveStimulusConfig(_ stimulus: StimulusConfig, on peripheral: CBPeripheral) async throws {
        try await writeConfig(stimulus, on: peripheral)
    }

    /// Alarm slot layout (hour, minute, day bitmask, enabled, id prefix) is
    /// unverified against real hardware — the alarm characteristics live in
    /// `kApplicationServiceUuid`, whose UUID is inferred the same way as the
    /// stimulus ones.
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
            to: LegacyGATT.applicationControl,
            serviceUUID: LegacyGATT.applicationService,
            on: peripheral
        )
    }

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
