import XCTest
@testable import Jolt

/// The automation keys are additions to the contract. A current server sends
/// them; an older one doesn't, and its friend list must still decode — a
/// failure there is swallowed by `refreshFriends`' `try?` and freezes the
/// list instead of erroring.
final class AutomationConsentDecodingTests: XCTestCase {
    private func friendJSON(zap: String) -> String {
        """
        {
          "id": "8b1e4b8e-3e4e-4c0e-9b3e-2a1b4c5d6e7f",
          "handle": "alice",
          "displayName": "Alice",
          "permissionsGrantedToMe": {
            "zap": \(zap),
            "vibe": { "isAllowed": false, "maxIntensity": 0, "cooldownSeconds": 60 },
            "beep": { "isAllowed": false, "maxIntensity": 0, "cooldownSeconds": 60 }
          },
          "permissionsIGranted": {
            "zap": \(zap),
            "vibe": { "isAllowed": false, "maxIntensity": 0, "cooldownSeconds": 60 },
            "beep": { "isAllowed": false, "maxIntensity": 0, "cooldownSeconds": 60 }
          }
        }
        """
    }

    func testDecodesAFriendFromAServerThatPredatesAutomationConsent() throws {
        let json = friendJSON(zap: #"{ "isAllowed": true, "maxIntensity": 30, "cooldownSeconds": 120 }"#)
        let friend = try JSONDecoder().decode(Friend.self, from: Data(json.utf8))
        let zap = friend.permissionsIGranted[.zap]
        XCTAssertTrue(zap.isAllowed)
        XCTAssertEqual(zap.maxIntensity, 30)
        XCTAssertNil(zap.automationAllowed)
        XCTAssertNil(zap.automationAllowedEffective)
        XCTAssertFalse(zap.supportsAutomationConsent)
    }

    func testDecodesAnUnansweredConsentFollowingTheServerDefault() throws {
        let json = friendJSON(zap: """
        { "isAllowed": true, "maxIntensity": 30, "cooldownSeconds": 120,
          "automationAllowed": null, "automationAllowedEffective": false }
        """)
        let friend = try JSONDecoder().decode(Friend.self, from: Data(json.utf8))
        let zap = friend.permissionsGrantedToMe[.zap]
        XCTAssertNil(zap.automationAllowed)
        XCTAssertEqual(zap.automationAllowedEffective, false)
        XCTAssertTrue(zap.supportsAutomationConsent)
    }

    func testDecodesAnExplicitConsent() throws {
        let json = friendJSON(zap: """
        { "isAllowed": true, "maxIntensity": 30, "cooldownSeconds": 120,
          "automationAllowed": true, "automationAllowedEffective": true }
        """)
        let friend = try JSONDecoder().decode(Friend.self, from: Data(json.utf8))
        XCTAssertEqual(friend.permissionsIGranted[.zap].automationAllowed, true)
        XCTAssertEqual(friend.permissionsIGranted[.zap].automationAllowedEffective, true)
    }

    /// Presets compare only the grant: an answered automation question must
    /// not stop "Trusted" from reading as the active preset.
    func testSameGrantIgnoresAutomationConsent() {
        var answered = StimulusPermission.allowed(maxIntensity: 60, cooldownSeconds: 15)
        answered.automationAllowed = false
        answered.automationAllowedEffective = false
        XCTAssertTrue(answered.hasSameGrant(as: .allowed(maxIntensity: 60, cooldownSeconds: 15)))
        XCTAssertFalse(answered.hasSameGrant(as: .allowed(maxIntensity: 61, cooldownSeconds: 15)))
        XCTAssertNotEqual(answered, .allowed(maxIntensity: 60, cooldownSeconds: 15))
    }

    func testKeepingAutomationConsentTakesTheGrantFromSelfAndTheAnswerFromOther() {
        var current = StimulusPermission.allowed(maxIntensity: 20, cooldownSeconds: 60)
        current.automationAllowed = true
        current.automationAllowedEffective = true
        let merged = StimulusPermission.disabled.keepingAutomationConsent(of: current)
        XCTAssertFalse(merged.isAllowed)
        XCTAssertEqual(merged.automationAllowed, true)
        XCTAssertEqual(merged.automationAllowedEffective, true)
    }
}
