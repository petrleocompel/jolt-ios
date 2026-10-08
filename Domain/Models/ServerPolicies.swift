import Foundation

/// Server-wide rules the app explains rather than enforces. Arrives with the
/// signed-in profile (`GET /me`, signup, login); nil from a server that
/// predates it.
struct ServerPolicies: Codable, Equatable {
    /// True: a friend's automated pokes (sent with their API tokens) are
    /// blocked until you allow them, per friend and stimulus. False: they
    /// are allowed unless you block them. Either way an explicit answer in
    /// `StimulusPermission.automationAllowed` wins.
    var automationConsentRequired: Bool

    /// What an unanswered `automationAllowed` currently means.
    var automationAllowedByDefault: Bool { !automationConsentRequired }
}
