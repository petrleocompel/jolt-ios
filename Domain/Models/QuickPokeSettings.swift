import Foundation

/// A one-tap "poke this friend" shortcut surfaced on the Remote tab.
///
/// Deliberately simpler than `PokeTrigger` — there's no device gesture to
/// learn, just a friend and a stimulus chosen once in Settings.
struct QuickPokeSettings: Codable, Equatable {
    /// Master switch. Settings can be fully configured and still hidden from
    /// Remote by toggling this off.
    var isEnabled: Bool

    /// Who gets poked. Stored alongside a display name so Remote and Settings
    /// can show it without a friends round-trip, but the ID is the source of
    /// truth.
    var targetFriendID: Friend.ID?
    var targetFriendName: String?

    /// What they receive. Subject to the recipient's own poke permissions,
    /// enforced server-side like any other poke.
    var stimulus: StimulusConfig

    static let `default` = QuickPokeSettings(
        isEnabled: false,
        targetFriendID: nil,
        targetFriendName: nil,
        stimulus: StimulusConfig(kind: .vibe, intensity: 30, repetitions: 1)
    )

    /// Enough to actually show the Remote-tab button.
    var isConfigured: Bool {
        isEnabled && targetFriendID != nil
    }
}
