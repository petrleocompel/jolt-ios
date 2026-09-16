import Foundation

/// Shared `UserDefaults` key for "I'll use Jolt without a wearable".
///
/// Pairing is a first-run *offer*, not a gate: Friends, sending and receiving
/// pokes, phone alarms and the saved stimulus defaults all work with no
/// device in range. This flag only records that the user answered the offer
/// with "not now", so the pairing screen isn't put in front of them again on
/// every launch — they can still pair later from Settings → Device or the
/// Remote tab's device card.
enum DevicePairing {
    static let didChooseNoDeviceKey = "cz.peelco.jolt.didChooseNoDevice"
}
