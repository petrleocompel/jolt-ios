import XCTest
@testable import Jolt

final class StimulusSettingsTests: XCTestCase {
    func testEachKindHasItsOwnIndependentConfig() {
        var settings = StimulusSettings.default
        settings[.zap] = StimulusConfig(kind: .zap, intensity: 15, repetitions: 1)
        settings[.vibe] = StimulusConfig(kind: .vibe, intensity: 90, repetitions: 3)

        XCTAssertEqual(settings[.zap].intensity, 15)
        XCTAssertEqual(settings[.vibe].intensity, 90)
        XCTAssertEqual(settings[.vibe].repetitions, 3)
        XCTAssertEqual(settings[.beep], StimulusSettings.default[.beep])
    }

    func testMissingKindFallsBackToTheDefaultForThatKind() {
        let settings = StimulusSettings()
        XCTAssertEqual(settings[.zap], StimulusSettings.default[.zap])
        XCTAssertEqual(settings[.beep], StimulusSettings.default[.beep])
    }

    func testCodableRoundTripPreservesEveryKind() throws {
        var settings = StimulusSettings.default
        settings[.zap] = StimulusConfig(kind: .zap, intensity: 42, repetitions: 2)

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(StimulusSettings.self, from: data)

        XCTAssertEqual(decoded, settings)
        XCTAssertEqual(decoded[.zap].intensity, 42)
        XCTAssertEqual(decoded[.zap].repetitions, 2)
    }

    func testDefaultZapIsGentlerThanDefaultVibe() {
        // Not a style preference: the first zap someone fires should not be
        // at the same level as a vibe they can barely feel.
        XCTAssertLessThan(StimulusSettings.default[.zap].intensity, StimulusSettings.default[.vibe].intensity)
    }
}

final class StimulusSettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "StimulusSettingsStoreTests-\(UUID().uuidString)")
    }

    func testLoadReturnsDefaultsWhenNothingSaved() {
        XCTAssertEqual(StimulusSettingsStore(defaults: defaults).load(), .default)
    }

    func testSavedSettingsSurviveAReload() {
        let store = StimulusSettingsStore(defaults: defaults)
        var settings = StimulusSettings.default
        settings[.beep] = StimulusConfig(kind: .beep, intensity: 77, repetitions: 4)
        store.save(settings)

        XCTAssertEqual(StimulusSettingsStore(defaults: defaults).load()[.beep].intensity, 77)
    }
}
