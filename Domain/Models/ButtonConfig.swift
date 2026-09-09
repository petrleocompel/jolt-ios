import Foundation

/// Which physical button, and how long it was held. Mirrors `DeviceButtonType`
/// from the Android app's `pavlok_flutter_ble` package — recovered by
/// disassembling `setButtonAction` and the raw event decoder
/// (`Utils.getDeviceButtonType`); see `docs/RE-FINDINGS.md` §3.
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
}

/// What a button press does. Mirrors `DeviceButtonActionType`. Wire values
/// recovered the same way as `DeviceButtonSlot` — see `docs/RE-FINDINGS.md`
/// §3. Every real case is modeled here so the picker reflects what the
/// device actually supports, but only `.disabled`'s write payload has been
/// confirmed against the disassembly; `CompositeDeviceRepository.setButtonConfig`
/// rejects the rest rather than guessing a stimulus-firing payload.
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
            return "\"\(action.displayName)\" isn't confirmed to work on real hardware yet — "
                + "only \"Off\" is currently supported."
        }
    }
}
