import XCTest

/// Proves the wearable is optional end to end: a launch that has never
/// paired one can decline the pairing offer, reach the whole app, and poke a
/// friend. Runs against `MockSocialBackend` (`-snapshotMode`) with
/// `-noDevice` forcing the "never paired" side of `FakeDeviceRepository`, so
/// the outcome doesn't depend on the simulator's absent Bluetooth stack.
final class DeviceFreeUsageUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        // `-snapshotMode` already resets persisted state, which is what keeps
        // an earlier run's "continue without a device" out of this one.
        app.launchArguments += ["-snapshotMode", "-noDevice"]
        app.launch()
        return app
    }

    /// Declines the first-run pairing offer and waits for the app proper.
    @MainActor
    @discardableResult
    private func launchAndDeclinePairing() -> XCUIApplication {
        let app = launchApp()
        let skipButton = app.buttons["continueWithoutDeviceButton"]
        XCTAssertTrue(skipButton.waitForExistence(timeout: 15), "First run should offer to skip pairing")
        skipButton.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["remoteControlScreen"].waitForExistence(timeout: 10),
            "Declining the pairing offer should land in the app, not back on pairing"
        )
        return app
    }

    @MainActor
    func testContinuingWithoutADeviceReachesTheApp() {
        let app = launchAndDeclinePairing()

        // The Remote tab is honest about what's missing, and offers the way
        // back. Queried by label, not identifier: the hero card's own
        // `deviceStatusRow` identifier propagates to all its children.
        XCTAssertTrue(app.staticTexts["No device paired"].exists)
        XCTAssertTrue(app.buttons["Pair a device"].exists)
        // Firing at a device we haven't got is the one thing that's off.
        XCTAssertFalse(app.buttons["fireButton_zap"].isEnabled)

        // Every tab is reachable, not just Remote, and Settings can pair later.
        XCTAssertTrue(app.selectTab("Alarms"))
        XCTAssertTrue(app.selectTab("Settings"))
        XCTAssertTrue(app.buttons["pairDeviceButton"].waitForExistence(timeout: 5))
        app.buttons["pairDeviceButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["pairDeviceSheet"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testPokingAFriendWorksWithNoDevice() {
        let app = launchAndDeclinePairing()

        XCTAssertTrue(app.selectTab("Friends"), "Friends tab should be reachable with no device")
        signUp(app)

        app.staticTexts["Alice"].tap()
        let sendPoke = app.buttons["sendPokeButton"]
        XCTAssertTrue(sendPoke.waitForExistence(timeout: 5))
        sendPoke.tap()

        // The poke has to land in the activity log as actually sent — with no
        // device of our own anywhere in the picture.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.staticTexts["Poke activity"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["pokeActivityList"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Alice'")).firstMatch
                .waitForExistence(timeout: 5)
        )
    }

    /// The pairing screen is a first-run offer; once declined it must not
    /// come back and take the app away again.
    @MainActor
    func testPairingOfferIsNotShownAgainAfterDeclining() {
        let app = launchAndDeclinePairing()

        // Relaunch without `-snapshotMode`'s state reset, the way a second
        // day of use looks.
        app.terminate()
        let relaunched = XCUIApplication()
        relaunched.launchArguments += ["-noDevice"]
        relaunched.launch()

        XCTAssertTrue(
            relaunched.descendants(matching: .any)["remoteControlScreen"].waitForExistence(timeout: 15),
            "A second launch should go straight to the app"
        )
        XCTAssertFalse(relaunched.buttons["continueWithoutDeviceButton"].exists)
    }

    @MainActor
    private func signUp(_ app: XCUIApplication) {
        let emailField = app.textFields["emailField"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 5))
        app.segmentedControls.buttons["Sign Up"].tap()

        emailField.tap()
        emailField.typeText("me@example.com")
        app.secureTextFields["passwordField"].tap()
        app.secureTextFields["passwordField"].typeText("password123")

        let handleField = app.textFields["Handle (e.g. alice)"]
        handleField.tap()
        handleField.typeText("me")

        let displayNameField = app.textFields["Display name"]
        displayNameField.tap()
        displayNameField.typeText("Me")

        app.buttons["authSubmitButton"].tap()
        XCTAssertTrue(app.staticTexts["Alice"].waitForExistence(timeout: 5))
    }
}
