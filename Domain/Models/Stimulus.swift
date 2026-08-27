import Foundation

/// One of the three physical outputs every Pavlok device can fire.
/// Names match the Android app's `zap` / `motor` (vibe) / `piezo` (beep) split.
enum StimulusKind: String, CaseIterable, Codable, Identifiable {
    case zap
    case vibe
    case beep

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .zap: return "Zap"
        case .vibe: return "Vibe"
        case .beep: return "Beep"
        }
    }

    /// Used in activity-log sentences ("Alice {verb} you") — `rawValue`
    /// alone reads wrong for zap ("zaped").
    var pastTenseVerb: String {
        switch self {
        case .zap: return "zapped"
        case .vibe: return "buzzed"
        case .beep: return "beeped"
        }
    }
}

/// Intensity is device-relative, not absolute volts/amps — the legacy and
/// SCMax protocols each map this 0...100 range onto their own hardware scale.
struct StimulusConfig: Codable, Equatable {
    var kind: StimulusKind
    var intensity: Int
    var repetitions: Int

    static let intensityRange = 0...100

    init(kind: StimulusKind, intensity: Int = 30, repetitions: Int = 1) {
        self.kind = kind
        self.intensity = intensity.clamped(to: Self.intensityRange)
        self.repetitions = max(1, repetitions)
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
