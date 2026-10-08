import XCTest
@testable import Jolt

/// The PUT body's `automationAllowed` has three meanings on the wire — and
/// "absent" is the one every ordinary edit must use, or moving a slider
/// would wipe an answer given on the dashboard.
final class StimulusPermissionUpdateTests: XCTestCase {
    private var answered: StimulusPermission {
        var permission = StimulusPermission.allowed(maxIntensity: 30, cooldownSeconds: 90)
        permission.automationAllowed = false
        permission.automationAllowedEffective = false
        return permission
    }

    private func encoded(_ update: StimulusPermissionUpdate) throws -> [String: Any] {
        let data = try JSONEncoder().encode(update)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testAnOrdinaryEditLeavesTheAnswerOut() throws {
        let body = try encoded(StimulusPermissionUpdate(answered))
        XCTAssertEqual(body["isAllowed"] as? Bool, true)
        XCTAssertEqual(body["maxIntensity"] as? Int, 30)
        XCTAssertEqual(body["cooldownSeconds"] as? Int, 90)
        XCTAssertNil(body["automationAllowed"], "absent means 'leave it alone' — even though the permission holds one")
        XCTAssertNil(body["automationAllowedEffective"])
    }

    func testAllowAndBlockAreSentExplicitly() throws {
        let allowed = try encoded(StimulusPermissionUpdate(answered, automation: .set(true)))
        XCTAssertEqual(allowed["automationAllowed"] as? Bool, true)

        let blocked = try encoded(StimulusPermissionUpdate(answered, automation: .set(false)))
        XCTAssertEqual(blocked["automationAllowed"] as? Bool, false)
        XCTAssertNil(blocked["automationAllowedEffective"])
    }

    func testResetToDefaultSendsAnExplicitNull() throws {
        let body = try encoded(StimulusPermissionUpdate(answered, automation: .resetToDefault))
        XCTAssertTrue(body.keys.contains("automationAllowed"))
        XCTAssertTrue(body["automationAllowed"] is NSNull)
    }

    func testAnAnswerMapsOntoTheMatchingChange() {
        XCTAssertEqual(StimulusPermissionUpdate.Automation(answer: true), .set(true))
        XCTAssertEqual(StimulusPermissionUpdate.Automation(answer: false), .set(false))
        XCTAssertEqual(StimulusPermissionUpdate.Automation(answer: nil), .resetToDefault)
    }
}
