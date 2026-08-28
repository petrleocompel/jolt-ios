import Foundation

/// Per-kind stimulus defaults.
///
/// The Android app keeps one config per output — `deviceZapConfig`,
/// `deviceMotorConfig`, `devicePiezoConfig` (getters confirmed in the Dart
/// snapshot, see `docs/RE-FINDINGS.md` §3) — rather than one shared
/// intensity. A comfortable vibe and a useful zap are nowhere near the same
/// number, so a single slider forces a re-adjustment on every switch.
struct StimulusSettings: Codable, Equatable {
    private var configsByKind: [StimulusKind: StimulusConfig]

    /// Defaults chosen to be safe on first launch: a zap starts low, a vibe
    /// and beep start at a level that is actually noticeable.
    static let `default` = StimulusSettings(configsByKind: [
        .zap: StimulusConfig(kind: .zap, intensity: 20, repetitions: 1),
        .vibe: StimulusConfig(kind: .vibe, intensity: 60, repetitions: 1),
        .beep: StimulusConfig(kind: .beep, intensity: 60, repetitions: 1)
    ])

    init(configsByKind: [StimulusKind: StimulusConfig] = [:]) {
        self.configsByKind = configsByKind
    }

    subscript(kind: StimulusKind) -> StimulusConfig {
        get { configsByKind[kind] ?? Self.default.configsByKind[kind] ?? StimulusConfig(kind: kind) }
        set { configsByKind[kind] = newValue }
    }

    var all: [StimulusConfig] {
        StimulusKind.allCases.map { self[$0] }
    }

    // `[StimulusKind: StimulusConfig]` encodes as an array under
    // `JSONEncoder` unless the key is a `String`, which makes the stored
    // blob unreadable and order-dependent. Round-tripping through
    // `[String: StimulusConfig]` keeps it a plain object.
    private enum CodingKeys: String, CodingKey {
        case configsByKind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode([String: StimulusConfig].self, forKey: .configsByKind)
        configsByKind = raw.reduce(into: [:]) { result, entry in
            guard let kind = StimulusKind(rawValue: entry.key) else { return }
            result[kind] = entry.value
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let raw = configsByKind.reduce(into: [String: StimulusConfig]()) { result, entry in
            result[entry.key.rawValue] = entry.value
        }
        try container.encode(raw, forKey: .configsByKind)
    }
}

/// Where a saved stimulus config ended up.
enum StimulusSyncState: Equatable {
    /// Stored on the phone only — the device either isn't connected or
    /// rejected the write.
    case localOnly(reason: String?)
    /// Stored on the phone and written to the wearable, so the device's own
    /// button and alarms use it too.
    case syncedToDevice
}
