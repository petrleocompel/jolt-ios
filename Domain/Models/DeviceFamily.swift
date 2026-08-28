import Foundation

/// The three hardware families Jolt talks to. Each has its own GATT layout
/// under `BLE/Legacy` (Pavlok 2 & 3) or `BLE/SCMax` (Shock Clock Max).
enum DeviceFamily: String, CaseIterable, Codable {
    case pavlok2
    case pavlok3
    case shockClockMax

    /// Pavlok 2/3 prefixes are confirmed from strings in the Android binary
    /// (`Pavlok-1`, `pavlok-2`, `pavlok-3`). Shock Clock Max's advertised
    /// name was not found there — the entries below are placeholders until
    /// confirmed against real hardware (see docs/RE-FINDINGS.md).
    ///
    /// Note what is deliberately *absent*: a bare `"Pavlok"` prefix. It used
    /// to be listed under `shockClockMax`, where it matched every Pavlok
    /// ever made — including a Pavlok 3, which then got routed to
    /// `SCMaxDeviceController` and threw `notImplemented` on every zap.
    /// It would also have swallowed `Pavlok-RingL` / `Pavlok-Smart-Ring`,
    /// which this app does not support at all.
    var advertisedNamePrefixes: [String] {
        switch self {
        case .pavlok2: return ["pavlok-2", "pavlok-1"]
        case .pavlok3: return ["pavlok-3"]
        case .shockClockMax: return ["shockclockmax", "shock-clock-max", "scmax"]
        }
    }

    var displayName: String {
        switch self {
        case .pavlok2: return "Pavlok 2"
        case .pavlok3: return "Pavlok 3"
        case .shockClockMax: return "Shock Clock Max"
        }
    }

    /// Match order, most specific first. `allCases` order happens to be
    /// right today, but relying on that would break silently if a case were
    /// ever reordered, and the previous code iterated a `Set` — whose order
    /// is not defined at all, so the same device could classify differently
    /// between launches.
    private static let matchOrder: [DeviceFamily] = [.pavlok3, .pavlok2, .shockClockMax]

    /// Classifies an advertised device name. Returns `nil` for anything not
    /// recognised — including Pavlok rings, which this app does not support.
    static func matching(name: String, in candidates: Set<DeviceFamily> = Set(allCases)) -> DeviceFamily? {
        let normalized = name.lowercased()
        return matchOrder.first { family in
            candidates.contains(family)
                && family.advertisedNamePrefixes.contains { normalized.contains($0) }
        }
    }
}
