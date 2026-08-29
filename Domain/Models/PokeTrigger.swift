import Foundation

/// "When I press *this* on my Pavlok, poke *this friend*."
///
/// Approach A from the `jolt-firmware` RE (device→phone→friend-poke) without
/// touching device firmware. The wearable already reports button presses to
/// the phone; we can't yet name the exact byte layout of a tap event (it's
/// compiled into firmware — see `jolt-firmware` `docs/04`), so instead of
/// decoding it we **learn it by example**: the user captures the event their
/// chosen gesture produces, and the trigger fires whenever that same event
/// recurs.
///
/// That keeps this correct today and forward-compatible: if the opcode is
/// pinned down later, a named-gesture picker can populate the same
/// `learnedCharacteristicUUID` / `learnedBytes` fields.
struct PokeTrigger: Codable, Equatable {
    /// Master switch. Even when on, the trigger only arms once a friend and a
    /// learned signature exist (`isArmed`).
    var isEnabled: Bool

    /// Who gets poked. Stored alongside a display name so Settings can show it
    /// without a friends round-trip, but the ID is the source of truth.
    var targetFriendID: Friend.ID?
    var targetFriendName: String?

    /// What they receive. Subject to the recipient's own poke permissions,
    /// enforced server-side like any other poke.
    var stimulus: StimulusConfig

    /// The captured event that arms the trigger: which characteristic it came
    /// from (canonical UUID) and the exact bytes.
    var learnedCharacteristicUUID: String?
    var learnedBytes: Data?

    /// How strictly a live event must match the learned one. `exact` is the
    /// default; `prefix` tolerates a trailing counter/timestamp some firmwares
    /// append to otherwise-identical events.
    enum MatchMode: String, Codable, CaseIterable {
        case exact
        case prefix
    }
    var matchMode: MatchMode

    /// Ignore repeats within this window, so one physical press sends one poke
    /// even if the device notifies more than once.
    var debounceSeconds: TimeInterval

    static let `default` = PokeTrigger(
        isEnabled: false,
        targetFriendID: nil,
        targetFriendName: nil,
        stimulus: StimulusConfig(kind: .vibe, intensity: 30, repetitions: 1),
        learnedCharacteristicUUID: nil,
        learnedBytes: nil,
        matchMode: .exact,
        debounceSeconds: 2
    )

    /// A configured, ready-to-fire trigger. `isEnabled` alone isn't enough —
    /// without a friend and a learned signature there's nothing to do.
    var isArmed: Bool {
        isEnabled && targetFriendID != nil && (learnedBytes != nil)
    }

    /// Whether `event` is the gesture this trigger was taught.
    func matches(_ event: DeviceEvent) -> Bool {
        guard let learnedChar = learnedCharacteristicUUID,
              let learnedBytes,
              event.characteristicUUID.caseInsensitiveCompare(learnedChar) == .orderedSame
        else { return false }
        switch matchMode {
        case .exact:
            return event.data == learnedBytes
        case .prefix:
            return !learnedBytes.isEmpty && event.data.starts(with: learnedBytes)
        }
    }
}
