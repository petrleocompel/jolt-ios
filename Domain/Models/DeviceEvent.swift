import Foundation

/// One unsolicited notification the wearable pushed to the phone — a timer
/// tick, a sleep-tracking change, a find-my-phone toggle, whatever the
/// firmware reports on one of its notify characteristics.
///
/// This is deliberately *raw*: service/characteristic (as canonical UUID
/// strings so `Features/` and `Domain/` never import CoreBluetooth) plus the
/// exact bytes. Decoding happens in the accessors below, and only as far as
/// the firmware disassembly actually supports.
struct DeviceEvent: Equatable, Codable, Identifiable {
    var id: UUID
    /// Canonical (long-form, upper-hex) service UUID — see `CBUUID.canonicalString`.
    var serviceUUID: String
    /// Canonical characteristic UUID.
    var characteristicUUID: String
    var data: Data
    var receivedAt: Date

    init(
        id: UUID = UUID(),
        serviceUUID: String,
        characteristicUUID: String,
        data: Data,
        receivedAt: Date = Date()
    ) {
        self.id = id
        self.serviceUUID = serviceUUID
        self.characteristicUUID = characteristicUUID
        self.data = data
        self.receivedAt = receivedAt
    }

    /// Space-separated upper-hex, matching the diagnostics capture log format.
    var hexString: String {
        data.isEmpty ? "(empty)" : data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    // MARK: The Events characteristic

    /// The events characteristic (`2002` of the notification service), in both
    /// forms a peripheral can report it.
    ///
    /// Pavlok services carry the vendor base `156Exxxx-A300-…` while their
    /// characteristics are plain 16-bit, so the same characteristic arrives as
    /// the Bluetooth-base expansion on real hardware — but a device (or a
    /// fixture) that declares it under the vendor base is equally valid. Both
    /// are accepted so a decode never silently fails on UUID form; see
    /// `CBUUID.canonicalString` for why this bites.
    static let eventsCharacteristicUUIDs: Set<String> = [
        "00002002-0000-1000-8000-00805F9B34FB",
        "156E2002-A300-4FEA-897B-86F698D74461"
    ]

    var isEventsCharacteristic: Bool {
        Self.eventsCharacteristicUUIDs.contains(characteristicUUID.uppercased())
    }

    /// Byte 0 of an events frame: *what happened*.
    ///
    /// The firmware builds every frame on this characteristic as
    /// `[eventType, payload…]` (`pavlok.bin` 6.8.0, `0x2E2C4`), with the
    /// payload one or two bytes depending on the type. The frame carries no
    /// button identity — see `findMyPhoneEventType`.
    var eventType: UInt8? {
        guard isEventsCharacteristic, let first = data.first else { return nil }
        return first
    }

    /// The event a find-my-phone button press produces.
    ///
    /// Pressing a button configured to `findMyPhone` runs the firmware's
    /// find-my-phone module, which — once a phone is connected — pushes
    /// `[0x0C, state, flag]` on the events characteristic so the phone can
    /// start (or stop) ringing. It is the one button-driven event the device
    /// is guaranteed to announce, which is what the poke trigger rides on.
    static let findMyPhoneEventType: UInt8 = 0x0C

    /// True when this frame is the find-my-phone announcement above.
    ///
    /// Note it says nothing about *which* button was pressed: the firmware
    /// doesn't put the button in the frame. Distinguishing presses means
    /// giving exactly one button the `findMyPhone` action.
    var isFindMyPhoneEvent: Bool {
        eventType == Self.findMyPhoneEventType
    }
}
