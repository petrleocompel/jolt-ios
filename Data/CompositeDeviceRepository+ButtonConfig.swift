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

    /// Asks the device what every button is currently set to.
    ///
    /// This is the half that was missing, and its absence is what made button
    /// config feel broken: the app could write an action and see the write
    /// acknowledged, but had no way to show what a button *was*, so every
    /// picker read "Device default" no matter what the device thought. Worse,
    /// a rejected write and an applied one looked identical in the UI.
    ///
    /// The sequence is the one `getDeviceButtonActions` uses, and it is not a
    /// GATT read — see `ButtonConfigReport` for why, and for the frame
    /// format. Subscribe to `7001` first, *then* write the query `01 01`,
    /// because the device starts pushing immediately and a subscription set
    /// up afterwards misses the burst.
    ///
    /// Collection is time-boxed rather than terminated by a sentinel: the
    /// report machine has no end-of-report frame we can rely on, so the
    /// window closes on a timer and whatever arrived gets parsed.
    func readButtonConfig() async throws -> ButtonConfigReport {
        let (peripheral, family) = try requireConnection()
        guard family != .shockClockMax else {
            throw SCMaxDeviceController.ControllerError.notImplemented(
                "Button config opcode not recovered — see BLE/SCMax/ProtocolMap.swift"
            )
        }

        let collector = ButtonConfigFrameCollector()
        let stream = try await central.subscribe(
            LegacyGATT.setupCharacteristic,
            in: LegacyGATT.setupService,
            on: peripheral
        )
        let task = Task { @MainActor in
            for await frame in stream where !frame.isEmpty {
                collector.append(frame)
            }
        }
        defer { task.cancel() }

        try await central.write(
            Data([0x01, 0x01]),
            to: LegacyGATT.setupCharacteristic,
            serviceUUID: LegacyGATT.setupService,
            on: peripheral
        )
        try? await Task.sleep(for: Self.buttonConfigReportWindow)

        let report = ButtonConfigReport.parse(frames: collector.frames)
        BLELog.info(
            "Button config report: \(report.frames.count) frame(s), "
                + "\(report.records.count) button(s) decoded"
        )
        return report
    }

    /// How long to keep collecting report frames after the query. Long enough
    /// for a twelve-entry burst at a normal connection interval, short enough
    /// that a device which answers nothing doesn't hang the screen.
    static var buttonConfigReportWindow: Duration { .milliseconds(1500) }

    /// The setup characteristic's current contents, raw.
    ///
    /// Note this is **not** the button config: the firmware's read-authorize
    /// handler answers a plain read of `7001` with a single status byte from
    /// its own state block (`0x2FAD4`), not with the stored actions. Use
    /// `readButtonConfig()` for the real thing. Kept because a read is
    /// harmless and the byte is still a live signal from the device.
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

/// Gathers report frames while the query is in flight. A tiny reference box
/// so the collecting task and the awaiting caller share one buffer without
/// `inout` capture games.
@MainActor
final class ButtonConfigFrameCollector {
    private(set) var frames: [Data] = []
    func append(_ frame: Data) { frames.append(frame) }
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
    /// | `defaultAction` | `00` | n/a — restores the firmware default |
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
        case .defaultAction:
            // Action byte `0x00` is not "no action" — `set_action`
            // (`0x2F3D8`) treats it as *restore this button's firmware
            // default*: it looks the button up in the default table via
            // `0x225FC` and copies that record instead of the payload. No
            // tail is read, so three bytes is the whole write.
            return Data(header + [0x00])
        case .zap, .beep, .vibrate, .airplaneMode, .doNotDisturb:
            return nil
        }
    }
}
