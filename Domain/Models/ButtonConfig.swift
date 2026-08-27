import Foundation

/// What the device's physical button does. Mirrors `ButtonConfigModel` /
/// `DeviceButtonEnums` from the Android app's `pavlok_flutter_ble` package.
enum ButtonPressType: String, CaseIterable, Codable {
    case singlePress
    case doublePress
    case longPress
}

enum ButtonAction: String, CaseIterable, Codable, Identifiable {
    case none
    case fireStimulus
    case toggleMute
    case snoozeActiveAlarm

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "Nothing"
        case .fireStimulus: return "Fire stimulus"
        case .toggleMute: return "Toggle mute"
        case .snoozeActiveAlarm: return "Snooze active alarm"
        }
    }
}

struct ButtonConfig: Codable, Equatable {
    var pressType: ButtonPressType
    var action: ButtonAction
    var stimulus: StimulusConfig?
}
