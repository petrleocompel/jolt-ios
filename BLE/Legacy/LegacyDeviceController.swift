import CoreBluetooth
import Foundation

/// Talks to Pavlok 2/3 over `LegacyGATT`. The wire format below (opcode byte
/// + intensity + repetitions) is a best-effort reconstruction from the
/// stimulus field names recovered in the Android binary (`zapIntensity`,
/// `zapCount`, `motorEnabled`, `piezoEnabled`) — it has not been verified
/// against a real device. If a zap/vibe/beep doesn't fire, capture a
/// reference payload (see `SCMaxProtocolMap` capture procedure — same idea,
/// simpler protocol) and fix the byte layout here; the call sites in
/// `Data/CompositeDeviceRepository.swift` don't need to change.
struct LegacyDeviceController {
    private let central: BluetoothCentralManager

    init(central: BluetoothCentralManager) {
        self.central = central
    }

    private enum Opcode: UInt8 {
        case zap = 0x01
        case vibe = 0x02
        case beep = 0x03
    }

    func fire(_ stimulus: StimulusConfig, on peripheral: CBPeripheral) async throws {
        let opcode: Opcode
        switch stimulus.kind {
        case .zap: opcode = .zap
        case .vibe: opcode = .vibe
        case .beep: opcode = .beep
        }
        let payload = Data([opcode.rawValue, UInt8(stimulus.intensity), UInt8(stimulus.repetitions)])
        try await central.write(
            payload,
            to: LegacyGATT.stimulusControlPoint,
            serviceUUID: LegacyGATT.service,
            on: peripheral
        )
    }

    /// Slot index + hour/minute/day-bitmask layout is a guess, same caveat
    /// as `fire(_:on:)` above — unverified against real hardware.
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
            to: LegacyGATT.alarmControlPoint,
            serviceUUID: LegacyGATT.service,
            on: peripheral
        )
    }

    func deleteAlarm(_ id: Alarm.ID, on peripheral: CBPeripheral) async throws {
        let payload = Data([0xFF]) + Data(id.uuidBytes.prefix(4))
        try await central.write(
            payload,
            to: LegacyGATT.alarmControlPoint,
            serviceUUID: LegacyGATT.service,
            on: peripheral
        )
    }
}

private extension UUID {
    var uuidBytes: [UInt8] {
        withUnsafeBytes(of: uuid) { Array($0) }
    }
}
