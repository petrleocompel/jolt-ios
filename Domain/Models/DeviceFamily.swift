import Foundation

/// The three hardware families Jolt talks to. Each has its own GATT layout
/// under `BLE/Legacy` (Pavlok 2 & 3) or `BLE/SCMax` (Shock Clock Max).
enum DeviceFamily: String, CaseIterable, Codable {
    case pavlok2
    case pavlok3
    case shockClockMax

    /// Pavlok 2/3 prefixes are confirmed from strings in the Android binary.
    /// Shock Clock Max's advertised name was not found there — placeholder
    /// until confirmed against real hardware (see docs/RE-FINDINGS.md).
    var advertisedNamePrefixes: [String] {
        switch self {
        case .pavlok2: return ["pavlok-2", "Pavlok-1"]
        case .pavlok3: return ["pavlok-3"]
        case .shockClockMax: return ["ShockClockMax", "SCMax", "Pavlok"]
        }
    }

    var displayName: String {
        switch self {
        case .pavlok2: return "Pavlok 2"
        case .pavlok3: return "Pavlok 3"
        case .shockClockMax: return "Shock Clock Max"
        }
    }
}
