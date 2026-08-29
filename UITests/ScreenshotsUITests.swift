import XCTest

/// App Store screenshots. Runs against `FakeDeviceRepository` (a fake
/// connected device, no real Bluetooth) via `-snapshotMode 1` — see
/// `App/AppEnvironment.swift` and docs/RE-FINDINGS.md screenshot contract.
final class ScreenshotsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        setupSnapshot(app)
        app.launchArguments += ["-snapshotMode", "1"]
        app.launch()
        return app
    }

    @MainActor
    func test01Remote() {
        let app = launchApp()
        XCTAssertTrue(app.descendants(matching: .any)["remoteControlScreen"].waitForExistence(timeout: 5))
        snapshot("01-Remote")
    }

    @MainActor
    func test02Alarms() {
        let app = launchApp()
        app.selectTab("Alarms")
        XCTAssertTrue(app.descendants(matching: .any)["alarmsList"].waitForExistence(timeout: 5))
        snapshot("02-Alarms")
    }

    @MainActor
    func test03AlarmEdit() {
        let app = launchApp()
        app.selectTab("Alarms")
        app.buttons["addAlarmButton"].tap()
        XCTAssertTrue(app.buttons["saveAlarmButton"].waitForExistence(timeout: 5))
        snapshot("03-AlarmEdit")
    }

    @MainActor
    func test04Settings() {
        let app = launchApp()
        app.selectTab("Settings")
        snapshot("04-Settings")
    }
}
