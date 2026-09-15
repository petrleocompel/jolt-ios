import Foundation

/// Which physical button, and how long it was held. Mirrors `DeviceButtonType`
/// from the Android app's `pavlok_flutter_ble` package, and matches the
/// firmware's own button table (`pavlok.bin` 6.8.0) — see
/// `docs/RE-FINDINGS.md` §3.
///
/// This is *not* a (button, pressType) pair layered on top of a shared
/// press-type axis — every button+duration combination has its own wire
/// value. There is no "double press" in the real protocol, and "long press"
/// isn't a modifier applied uniformly to one button: each button has its own
/// dedicated long-press identity.
enum DeviceButtonSlot: String, CaseIterable, Codable, Identifiable {
    case top
    case topLong
    case middle
    case middleLong
    case bottom
    case bottomLong
    case backLong

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .top: return "Top"
        case .topLong: return "Top (long press)"
        case .middle: return "Middle"
        case .middleLong: return "Middle (long press)"
        case .bottom: return "Bottom"
        case .bottomLong: return "Bottom (long press)"
        case .backLong: return "Back (long press)"
        }
    }

    /// The byte the device uses for this button: `setButtonAction`'s second
    /// payload byte, and the index into the firmware's per-button action
    /// table. The firmware validates it as `1...6` and rejects anything else
    /// (`0x07`/`backLong` included), so these are not free-form.
    ///
    /// This byte does **not** appear in incoming press notifications — the
    /// device never reports *which* button was pressed. See
    /// `docs/RE-FINDINGS.md` §3.
    var wireValue: UInt8 {
        switch self {
        case .top: return 0x01
        case .middle: return 0x02
        case .bottom: return 0x03
        case .topLong: return 0x04
        case .middleLong: return 0x05
        case .bottomLong: return 0x06
        case .backLong: return 0x07
        }
    }

    /// Decodes a button byte from a device config frame.
    ///
    /// `0x07` (`backLong`) is deliberately **not** decoded: the firmware's
    /// write handler rejects a button byte outside `1...6`, the Android app's
    /// `setButtonAction` early-returns for it, and its `getDeviceButtonType`
    /// has no case for it either — so `0x07` is a value we can neither write
    /// nor trust.
    init?(wireValue: UInt8) {
        guard let match = Self.allCases.first(where: { $0 != .backLong && $0.wireValue == wireValue })
        else { return nil }
        self = match
    }

    /// The slots that can actually be configured. `backLong` is excluded for
    /// the reason in `init?(wireValue:)`.
    static var configurableCases: [DeviceButtonSlot] { allCases.filter { $0 != .backLong } }
}

/// What a button press does. Mirrors `DeviceButtonActionType`. Wire values
/// and payload lengths are cross-checked against **both** the Android app's
/// `setButtonAction` and the firmware's own length table — see
/// `docs/RE-FINDINGS.md` §3. Every real case is modeled here so the picker
/// reflects what the device supports; `CompositeDeviceRepository.setButtonConfig`
/// writes only the ones whose full payload is known, because the firmware
/// rejects a payload of the wrong length outright.
enum ButtonAction: String, CaseIterable, Codable, Identifiable {
    case findMyPhone
    case stopWatch
    case timer
    case zap
    case beep
    case vibrate
    case toggleCandle
    case nextTune
    case airplaneMode
    case doNotDisturb
    case toggleSleepTracking
    case disabled
    case defaultAction

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .findMyPhone: return "Find my phone"
        case .stopWatch: return "Stopwatch"
        case .timer: return "Timer"
        case .zap: return "Zap"
        case .beep: return "Beep"
        case .vibrate: return "Vibrate"
        case .toggleCandle: return "Toggle candle"
        case .nextTune: return "Next tune"
        case .airplaneMode: return "Airplane mode"
        case .doNotDisturb: return "Do not disturb"
        case .toggleSleepTracking: return "Toggle sleep tracking"
        case .disabled: return "Off"
        case .defaultAction: return "Device default"
        }
    }
}

extension ButtonAction {
    /// Actions the *phone* has to carry out, which the device therefore has
    /// to report over BLE for them to work at all. Setting a button to one of
    /// these is what makes a press reach the app at all — a device-local
    /// action (zap, candle, timer) is handled inside the firmware and is
    /// never announced. See `jolt-firmware/docs/04-device-event-protocol.md`.
    var isPhoneSideEffect: Bool {
        switch self {
        case .findMyPhone, .nextTune, .airplaneMode, .doNotDisturb, .toggleSleepTracking:
            return true
        case .stopWatch, .timer, .zap, .beep, .vibrate, .toggleCandle, .disabled, .defaultAction:
            return false
        }
    }
}

struct ButtonConfig: Codable, Equatable {
    var slot: DeviceButtonSlot
    var action: ButtonAction
}

enum ButtonConfigError: LocalizedError {
    case slotUnsupported(DeviceButtonSlot)
    case actionNotVerified(ButtonAction)

    var errorDescription: String? {
        switch self {
        case .slotUnsupported(let slot):
            return "\(slot.displayName) can't be configured from the app yet."
        case .actionNotVerified(let action):
            return "\"\(action.displayName)\" has no recovered wire format yet — "
                + "\"Find my phone\", \"Off\", \"Stopwatch\", \"Timer\", \"Next tune\", "
                + "\"Toggle candle\" and \"Toggle sleep tracking\" can be written."
        }
    }
}
