import XCTest

/// Design-reference screenshots: walks every screen reachable in snapshot
/// mode so the whole app can be handed to a designer. Not App Store
/// screenshots — run via `bundle exec fastlane design_screenshots`, which
/// captures this class in light and dark mode into
/// `fastlane/design_screenshots/`.
///
/// Soft by design: a missing element skips that one screenshot rather than
/// failing the run, so one renamed identifier doesn't cost the whole set.
final class DesignReferenceUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        setupSnapshot(app)
        app.launchArguments += ["-snapshotMode", "1"]
        app.launch()
        return app
    }

    // MARK: - Remote

    @MainActor
    func test01Remote() {
        let app = launchApp()
        guard element("remoteControlScreen", in: app).waitForExistence(timeout: 10) else { return }
        snapshot("01-Remote-Dashboard")

        if tap(app.buttons["stimulusCard_zap"], in: app) {
            snapshot("02-Remote-StimulusEditor")
            tap(app.buttons["Cancel"], in: app)
        }

        if tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Customize'")).firstMatch, in: app) {
            snapshot("03-Remote-Customize")
            tap(app.buttons["Done"], in: app)
        }

        if tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'More info'")).firstMatch, in: app) {
            snapshot("04-Remote-DeviceDetail")
            if tap(app.buttons.matching(NSPredicate(format: "label CONTAINS 'diagnostics'")).firstMatch, in: app) {
                snapshot("05-Remote-Diagnostics")
                back(app)
            }
            if tap(app.buttons["Button configuration"], in: app) {
                snapshot("06-Remote-ButtonConfig")
                back(app)
            }
        }
    }

    // MARK: - Alarms

    @MainActor
    func test02Alarms() {
        let app = launchApp()
        app.selectTab("Alarms")
        guard element("alarmsList", in: app).waitForExistence(timeout: 5) else { return }
        snapshot("10-Alarms-List")

        if tap(app.staticTexts["Wake up"], in: app) {
            snapshot("11-Alarms-EditExisting")
            app.swipeUp()
            snapshot("12-Alarms-EditExisting-Bottom")
            tap(app.buttons["Cancel"], in: app)
        }

        if tap(app.buttons["addAlarmButton"], in: app) {
            snapshot("13-Alarms-New")
            tap(app.buttons["Cancel"], in: app)
        }
    }

    // MARK: - Friends, then everything that needs friends

    @MainActor
    func test03FriendsAndPokes() {
        let app = launchApp()
        app.selectTab("Friends")
        guard app.textFields["emailField"].waitForExistence(timeout: 5) else { return }
        snapshot("20-Friends-SignIn")

        app.segmentedControls.buttons["Sign Up"].tap()
        snapshot("21-Friends-SignUp")
        signUp(app)
        guard app.staticTexts["Alice"].waitForExistence(timeout: 5) else { return }
        snapshot("22-Friends-List")

        if tap(app.buttons["addFriendButton"], in: app) {
            snapshot("23-Friends-AddFriend")
            tap(app.buttons["Close"], in: app)
        }

        if tap(element("profileLink", in: app), in: app) {
            snapshot("24-Friends-Profile")
            back(app)
        }

        if tap(app.staticTexts["Poke activity"], in: app) {
            snapshot("25-Friends-Activity")
            back(app)
        }

        if tap(app.staticTexts["Bob"], in: app) {
            snapshot("26-Friends-Detail-NothingAllowed")
            back(app)
        }

        if tap(app.staticTexts["Alice"], in: app) {
            snapshot("27-Friends-Detail-Composer")
            if tap(app.staticTexts["Permissions you've granted Alice"], in: app) {
                snapshot("28-Friends-Permissions")
                app.swipeUp()
                snapshot("29-Friends-Permissions-Bottom")
                back(app)
            }
            back(app)
        }

        // Quick poke + poke trigger only have content once there are friends.
        app.selectTab("Settings")
        if tap(element("quickPokeSettingsLink", in: app), in: app) {
            snapshot("30-Settings-QuickPoke-Off")
            let toggle = app.switches["quickPokeEnableToggle"]
            if toggle.waitForExistence(timeout: 5) {
                toggle.switches.firstMatch.tap()
                if tap(element("quickPokeFriendPicker", in: app), in: app) {
                    tap(app.buttons["Alice"].firstMatch, in: app)
                }
                snapshot("31-Settings-QuickPoke-On")
            }
            back(app)
        }

        if tap(element("pokeTriggerSettingsLink", in: app), in: app) {
            let toggle = app.switches["pokeTriggerEnableToggle"]
            if toggle.waitForExistence(timeout: 5) {
                toggle.switches.firstMatch.tap()
                _ = element("pokeTriggerFriendPicker", in: app).waitForExistence(timeout: 5)
            }
            snapshot("32-Settings-PokeTrigger")
            app.swipeUp()
            snapshot("33-Settings-PokeTrigger-Bottom")
            back(app)
        }

        app.selectTab("Remote")
        if element("remoteControlScreen", in: app).waitForExistence(timeout: 5) {
            app.swipeUp()
            snapshot("34-Remote-WithQuickPoke")
            if tap(app.buttons["quickPokeComposerButton"], in: app) {
                _ = element("quickPokeComposerSheet", in: app).waitForExistence(timeout: 10)
                snapshot("35-Remote-QuickPokeComposer")
                tap(app.buttons["Close"], in: app)
            }
        }
    }

    // MARK: - Settings

    @MainActor
    func test04Settings() {
        let app = launchApp()
        app.selectTab("Settings")
        snapshot("40-Settings")
        app.swipeUp()
        snapshot("41-Settings-Bottom")
        app.swipeDown()

        let pages: [(id: String, name: String)] = [
            ("firingModesSettingsLink", "42-Settings-Firing"),
            ("pokeFeedbackSettingsLink", "43-Settings-PokeFeedback"),
            ("notificationTestLink", "44-Settings-Notifications"),
            ("pavlokAccountLink", "45-Settings-PavlokAccount"),
            ("serverSettingsLink", "46-Settings-Server")
        ]
        for page in pages where tap(element(page.id, in: app), in: app) {
            snapshot(page.name)
            back(app)
        }

        if tap(app.staticTexts["About"], in: app) {
            snapshot("47-Settings-About")
            back(app)
        }
    }

    // MARK: - No device

    /// `-noDevice` launches as if nothing was ever paired: first the pairing
    /// offer, then — after "Continue without a device" — the app's device-free
    /// states and the pairing sheet reachable from them.
    @MainActor
    func test05NoDevice() {
        let app = XCUIApplication()
        setupSnapshot(app)
        app.launchArguments += ["-snapshotMode", "1", "-noDevice"]
        app.launch()

        guard app.buttons["toggleScanButton"].waitForExistence(timeout: 10) else { return }
        snapshot("50-Onboarding")
        app.buttons["toggleScanButton"].tap()
        sleep(2)
        snapshot("51-Onboarding-Scanning")
        app.buttons["toggleScanButton"].tap()

        guard tap(app.buttons["continueWithoutDeviceButton"], in: app) else { return }
        if element("remoteControlScreen", in: app).waitForExistence(timeout: 5) {
            snapshot("01b-Remote-NoDevice")
        }

        app.selectTab("Settings")
        snapshot("40b-Settings-NoDevice")
        if tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Pair'")).firstMatch, in: app) {
            _ = app.buttons["toggleScanButton"].waitForExistence(timeout: 5)
            snapshot("52-PairDevice")
        }
    }

    // MARK: - Helpers

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    /// Scrolls to and taps `element`; returns false instead of failing when it
    /// never shows up. Lists are lazy — an off-screen row isn't in the
    /// hierarchy at all — so this scrolls until it exists *and* is hittable,
    /// down first, then back up in case an earlier page left us scrolled past.
    @MainActor
    @discardableResult
    private func tap(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        _ = element.waitForExistence(timeout: 3)
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < 6 {
            app.swipeUp()
            swipes += 1
        }
        while !(element.exists && element.isHittable) && swipes < 18 {
            app.swipeDown()
            swipes += 1
        }
        guard element.exists, element.isHittable else { return false }
        element.tap()
        return true
    }

    @MainActor
    private func back(_ app: XCUIApplication) {
        let button = app.navigationBars.buttons.element(boundBy: 0)
        if button.waitForExistence(timeout: 3) { button.tap() }
    }

    @MainActor
    private func signUp(_ app: XCUIApplication) {
        let emailField = app.textFields["emailField"]
        emailField.tap()
        emailField.typeText("me@example.com")
        app.secureTextFields["passwordField"].tap()
        app.secureTextFields["passwordField"].typeText("password123")
        let handleField = app.textFields["Handle (e.g. alice)"]
        handleField.tap()
        handleField.typeText("petr")
        let displayNameField = app.textFields["Display name"]
        displayNameField.tap()
        displayNameField.typeText("Petr")
        app.buttons["authSubmitButton"].tap()
    }
}
