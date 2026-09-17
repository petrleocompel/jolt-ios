import UserNotifications
import XCTest
@testable import Jolt

/// Covers the ringing/challenge flow's pure logic: snooze scheduling, the
/// saved QR dismiss code, which challenges can be switched to, and the math
/// puzzle's multiple-choice answers.
final class AlarmDismissFlowTests: XCTestCase {
    // MARK: - Snooze

    func testSnoozeFiresNineMinutesLater() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(PhoneAlarmScheduler.snoozeFireDate(from: now), now.addingTimeInterval(540))
    }

    func testSnoozeRequestIsOneOffAndReopensTheSameAlarm() throws {
        let alarm = Alarm(location: .phone, hour: 7, minute: 0, label: "Wake up", dismissChallenge: .mathPuzzle)
        let request = PhoneAlarmScheduler.makeSnoozeRequest(for: alarm, now: Date())

        let trigger = try XCTUnwrap(request.trigger as? UNTimeIntervalNotificationTrigger)
        XCTAssertEqual(trigger.timeInterval, 540, accuracy: 0.001)
        XCTAssertFalse(trigger.repeats)
        XCTAssertEqual(request.content.userInfo["alarmID"] as? String, alarm.id.uuidString)
        XCTAssertEqual(request.content.title, "Wake up")
        // `cancel(_:)` removes by alarm-ID prefix, so a deleted alarm's
        // pending snooze goes with it.
        XCTAssertTrue(request.identifier.hasPrefix(alarm.id.uuidString))
    }

    // MARK: - Saved QR code

    func testAlarmWithSavedCodeOnlyAcceptsThatCode() {
        let alarm = Alarm(location: .phone, hour: 7, minute: 0, dismissChallenge: .qrCodeScan, dismissQRCode: "bathroom")
        XCTAssertTrue(alarm.acceptsDismissCode("bathroom"))
        XCTAssertFalse(alarm.acceptsDismissCode("cereal-box"))
    }

    func testAlarmWithoutSavedCodeAcceptsAnyCode() {
        let alarm = Alarm(location: .phone, hour: 7, minute: 0, dismissChallenge: .qrCodeScan)
        XCTAssertTrue(alarm.acceptsDismissCode("anything"))
    }

    func testSavedCodeSurvivesPersistenceMapping() throws {
        let alarm = Alarm(location: .phone, hour: 6, minute: 30, dismissChallenge: .qrCodeScan, dismissQRCode: "code-123")
        let entity = try XCTUnwrap(alarm.makeEntity())
        XCTAssertEqual(Alarm(entity: entity), alarm)
    }

    func testAlarmJSONWithoutSavedCodeStillDecodes() throws {
        let original = Alarm(location: .device, hour: 8, minute: 15)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json.removeValue(forKey: "dismissQRCode")
        let decoded = try JSONDecoder().decode(Alarm.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded, original)
        XCTAssertNil(decoded.dismissQRCode)
    }

    // MARK: - Switching challenge

    func testQRIsNotOfferedAsAnEscapeWithoutASavedCode() {
        let alarm = Alarm(location: .phone, hour: 7, minute: 0, dismissChallenge: .mathPuzzle)
        XCTAssertEqual(ActiveAlarmView.switchableChallenges(for: alarm, current: .mathPuzzle), [.jumpingJacks])
    }

    func testQRIsOfferedWhenACodeIsSaved() {
        let alarm = Alarm(location: .phone, hour: 7, minute: 0, dismissChallenge: .mathPuzzle, dismissQRCode: "x")
        XCTAssertEqual(ActiveAlarmView.switchableChallenges(for: alarm, current: .jumpingJacks), [.mathPuzzle, .qrCodeScan])
    }

    func testLegacyQRAlarmCanSwitchBackToQR() {
        let alarm = Alarm(location: .phone, hour: 7, minute: 0, dismissChallenge: .qrCodeScan)
        XCTAssertEqual(ActiveAlarmView.switchableChallenges(for: alarm, current: .mathPuzzle), [.jumpingJacks, .qrCodeScan])
        XCTAssertEqual(ActiveAlarmView.switchableChallenges(for: alarm, current: .qrCodeScan), [.mathPuzzle, .jumpingJacks])
    }

    // MARK: - Math puzzle

    func testMathChoicesAreThreeDistinctNonNegativeValuesIncludingTheAnswer() {
        for _ in 0..<500 {
            let problem = MathProblem.random()
            XCTAssertEqual(problem.choices.count, 3, problem.question)
            XCTAssertEqual(Set(problem.choices).count, 3, problem.question)
            XCTAssertTrue(problem.choices.contains(problem.answer), problem.question)
            XCTAssertTrue(problem.choices.allSatisfy { $0 >= 0 }, problem.question)
        }
    }

    func testZeroAnswerStillGetsTwoDistractors() {
        let problem = MathProblem(firstOperand: 5, secondOperand: 5, operation: .subtract)
        XCTAssertEqual(problem.answer, 0)
        XCTAssertEqual(Set(problem.choices).count, 3)
        XCTAssertTrue(problem.choices.allSatisfy { $0 >= 0 })
    }
}
