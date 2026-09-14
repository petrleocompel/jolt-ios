import Foundation

/// "When I press *this* on my Pavlok, poke *this friend*."
///
/// Approach A from the `jolt-firmware` RE (device→phone→friend-poke) without
/// touching device firmware: the wearable already reports button presses to
/// the phone, so a press becomes an outgoing poke.
///
/// There are two ways to say *which* press:
///
/// - `buttonSlot` — the decoded one, and the default. Byte 2 of an events
///   notification is the `DeviceButtonType` (`docs/RE-FINDINGS.md` §3), so
///   "top, long press" is a real selection rather than a captured blob.
/// - `learnedCharacteristicUUID` / `learnedBytes` — learn-by-example, kept as
///   the fallback for frames the decoder doesn't recognise.
///
/// Note that a press only reaches the phone if the button is configured to an
/// action the phone has to perform (`ButtonAction.isPhoneSideEffect`); a
/// device-local action like zap is handled in firmware and may never be
/// announced. `PokeTriggerService.makeButtonReportPresses()` sets that up.
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

    /// The button whose press sends the poke, decoded from the event frame
    /// (`DeviceEvent.buttonSlot`). This is the preferred way to arm the
    /// trigger now that the button byte is recovered: it survives any trailing
    /// counter the firmware appends, and short vs. long press are genuinely
    /// distinct values rather than phone-side timing.
    ///
    /// When set, it takes precedence over the learned signature below.
    var buttonSlot: DeviceButtonSlot?

    /// The captured event that arms the trigger: which characteristic it came
    /// from (canonical UUID) and the exact bytes.
    ///
    /// Kept as the fallback for anything the decoder doesn't recognise — a
    /// press that arrives on another characteristic, or a frame whose byte 2
    /// isn't a known button value.
    var learnedCharacteristicUUID: String?
    var learnedBytes: Data?

    /// How strictly a live event must match the learned one. `exact` is the
    /// default; `prefix` tolerates a trailing counter/timestamp some firmwares
    /// append to otherwise-identical events.
    enum MatchMode: String, Codable, CaseIterable, Identifiable {
        case exact
        case prefix

        /// How many leading bytes `.prefix` compares.
        ///
        /// Three, because that is exactly the decoded header: byte 2 is the
        /// `DeviceButtonType` and everything after it is what varies between
        /// two presses of the same button. Comparing the *whole* learned frame
        /// (what this used to do) can never tolerate a trailing counter —
        /// learned `01 02 01 5A` vs. live `01 02 01 5B` fails a `starts(with:)`
        /// test just as it fails an equality test, which made this mode a
        /// no-op in practice.
        static let toleratedPrefixLength = 3

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .exact: return "Exact"
            case .prefix: return "Tolerant"
            }
        }
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
        buttonSlot: nil,
        learnedCharacteristicUUID: nil,
        learnedBytes: nil,
        matchMode: .exact,
        debounceSeconds: 2
    )

    /// A configured, ready-to-fire trigger. `isEnabled` alone isn't enough —
    /// without a friend and *some* gesture (a chosen button or a learned
    /// signature) there's nothing to do.
    var isArmed: Bool {
        isEnabled && targetFriendID != nil && (buttonSlot != nil || learnedBytes != nil)
    }

    /// Whether `event` is the press this trigger fires on.
    func matches(_ event: DeviceEvent) -> Bool {
        if let buttonSlot {
            return event.buttonSlot == buttonSlot
        }
        return matchesLearnedSignature(event)
    }

    private func matchesLearnedSignature(_ event: DeviceEvent) -> Bool {
        guard let learnedChar = learnedCharacteristicUUID,
              let learnedBytes, !learnedBytes.isEmpty,
              event.characteristicUUID.caseInsensitiveCompare(learnedChar) == .orderedSame
        else { return false }
        switch matchMode {
        case .exact:
            return event.data == learnedBytes
        case .prefix:
            let length = min(learnedBytes.count, MatchMode.toleratedPrefixLength)
            guard event.data.count >= length else { return false }
            return event.data.prefix(length).elementsEqual(learnedBytes.prefix(length))
        }
    }
}
