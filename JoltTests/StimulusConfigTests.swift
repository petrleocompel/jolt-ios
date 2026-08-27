import XCTest
@testable import Jolt

final class StimulusConfigTests: XCTestCase {
    func testIntensityClampsToValidRange() {
        XCTAssertEqual(StimulusConfig(kind: .zap, intensity: -10).intensity, 0)
        XCTAssertEqual(StimulusConfig(kind: .zap, intensity: 500).intensity, 100)
        XCTAssertEqual(StimulusConfig(kind: .zap, intensity: 50).intensity, 50)
    }

    func testRepetitionsAreAtLeastOne() {
        XCTAssertEqual(StimulusConfig(kind: .beep, repetitions: 0).repetitions, 1)
        XCTAssertEqual(StimulusConfig(kind: .beep, repetitions: -5).repetitions, 1)
    }
}
