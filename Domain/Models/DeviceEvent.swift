import Foundation

/// One unsolicited notification the wearable pushed to the phone — a button
/// press, hand-detect, alarm fire, timer tick, whatever the firmware reports
/// on one of its notify characteristics.
///
/// This is deliberately *raw*: service/characteristic (as canonical UUID
/// strings so `Features/` and `Domain/` never import CoreBluetooth) plus the
/// exact bytes. We do **not** pretend to decode the tap opcode here — its byte
/// layout is compiled into device firmware and isn't recovered yet (see the
/// `jolt-firmware` repo, `docs/04-device-event-protocol.md`).
///
/// The poke trigger works by *matching* these raw events against one the user
/// captured on purpose ("learn by example"), which sidesteps the unknown
/// encoding entirely and stays correct even once we do decode it.
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

    // MARK: Button presses

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

    var isButtonEventCharacteristic: Bool {
        Self.eventsCharacteristicUUIDs.contains(characteristicUUID.uppercased())
    }

    /// Which button this notification reports, if it is one.
    ///
    /// Byte 2 of an events frame carries the `DeviceButtonType` wire value —
    /// recovered from the Android app's own event decoder, `docs/RE-FINDINGS.md`
    /// §3. Short and long press are *different values here*, not a duration
    /// measured on the phone, so decoding this is strictly better than
    /// byte-matching a captured frame: it is immune to any trailing counter
    /// the firmware appends.
    var buttonSlot: DeviceButtonSlot? {
        guard isButtonEventCharacteristic, data.count > 2 else { return nil }
        return DeviceButtonSlot(wireValue: data[data.startIndex + 2])
    }
}
