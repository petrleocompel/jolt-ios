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
}
