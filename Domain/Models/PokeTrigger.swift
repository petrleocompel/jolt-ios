import Foundation

/// "When I press *this* on my Pavlok, poke *this friend*."
///
/// Approach A from the `jolt-firmware` RE (device→phone→friend-poke) without
/// touching device firmware.
///
/// How it actually works, which is narrower than it first looks: the device
/// does **not** broadcast button presses. It only announces a press whose
/// configured action the *phone* has to carry out. So the trigger is a pair:
///
/// 1. `buttonSlot` — the button we reconfigure to `findMyPhone`, the one
///    phone-side action whose payload is recovered
///    (`PokeTriggerService.makeButtonReportPresses()` writes it).
/// 2. the resulting announcement — `[0x0C, …]` on the events characteristic
///    (`DeviceEvent.isFindMyPhoneEvent`) — which is what `matches` fires on.
///
/// The frame carries no button identity, so only one button at a time can be
/// the poke button; that's a firmware limit, not a shortcut here.
/// `learnedCharacteristicUUID` / `learnedBytes` stay as the escape hatch for
/// firmware that announces something else.
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

    /// The button whose press sends the poke — i.e. the button the app sets
    /// to `findMyPhone` so the device announces it at all.
    ///
    /// Setting this is what switches the trigger to the decoded path: it then
    /// matches the announcement rather than a captured blob, and the learned
    /// signature below is ignored.
    var buttonSlot: DeviceButtonSlot?

    /// The captured event that arms the trigger: which characteristic it came
    /// from (canonical UUID) and the exact bytes.
    ///
    /// Kept as the fallback for anything the decoder doesn't recognise — a
    /// firmware that announces presses some other way, or on some other
    /// characteristic.
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
        /// One, because byte 0 of an events frame is the event type and every
        /// byte after it is state that changes between two presses of the same
        /// button — a find-my-phone toggle alternates `0C 01 xx` / `0C 00 00`.
        /// Comparing the *whole* learned frame (what this used to do) can
        /// never tolerate a varying tail: learned `0C 01 5A` vs. live
        /// `0C 01 5B` fails a `starts(with:)` test just as it fails an
        /// equality test, which made this mode a no-op in practice.
        static let toleratedPrefixLength = 1

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
    ///
    /// With a button chosen, that means the find-my-phone announcement — the
    /// device's way of saying "the button you configured was pressed". The
    /// per-press debounce in `PokeTriggerService` is what keeps the toggle's
    /// second frame from sending a second poke.
    func matches(_ event: DeviceEvent) -> Bool {
        if buttonSlot != nil {
            return event.isFindMyPhoneEvent
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
