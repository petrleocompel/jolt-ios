import Foundation

/// Body of `PUT /friends/{friendId}/permissions/{stimulusKind}`.
///
/// Not `StimulusPermission` itself. The grant's three keys overwrite, but
/// `automationAllowed` is three-valued on the wire: absent leaves the stored
/// answer alone, `true`/`false` set it, and `null` resets it to the server's
/// default. Synthesized `Encodable` can omit a nil but never send one — and
/// sending the permission as read back would echo the read-only
/// `automationAllowedEffective` too.
struct StimulusPermissionUpdate: Encodable, Equatable {
    enum Automation: Equatable {
        /// Leave the stored answer alone. Every ordinary edit sends this, so
        /// moving a slider — or applying a preset — can never wipe an answer
        /// given here or on the web dashboard.
        case unchanged
        case set(Bool)
        /// Back to "no answer", which follows the server's policy.
        case resetToDefault

        /// The change that leaves `automationAllowed` equal to `answer`.
        init(answer: Bool?) {
            self = answer.map(Automation.set) ?? .resetToDefault
        }
    }

    var isAllowed: Bool
    var maxIntensity: Int
    var cooldownSeconds: Int
    var automation: Automation

    init(_ permission: StimulusPermission, automation: Automation = .unchanged) {
        isAllowed = permission.isAllowed
        maxIntensity = permission.maxIntensity
        cooldownSeconds = permission.cooldownSeconds
        self.automation = automation
    }

    private enum CodingKeys: String, CodingKey {
        case isAllowed, maxIntensity, cooldownSeconds, automationAllowed
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isAllowed, forKey: .isAllowed)
        try container.encode(maxIntensity, forKey: .maxIntensity)
        try container.encode(cooldownSeconds, forKey: .cooldownSeconds)
        switch automation {
        case .unchanged:
            break
        case .set(let allowed):
            try container.encode(allowed, forKey: .automationAllowed)
        case .resetToDefault:
            try container.encodeNil(forKey: .automationAllowed)
        }
    }
}
