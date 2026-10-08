import XCTest

/// Exercises the real sign-up → friends list flow end to end against
/// `MockSocialBackend`, not just the backend in isolation — proves the
/// AuthView/FriendsListView wiring actually works, not just the model layer.
final class FriendsFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-snapshotMode", "1"]
        app.launch()
        return app
    }

    @MainActor
    func testSignUpRevealsSeededFriendsList() {
        let app = launchApp()
        app.selectTab("Friends")

        let emailField = app.textFields["emailField"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 5))

        // Switch to Sign Up mode.
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

        let friendsList = app.descendants(matching: .any)["friendsList"]
        XCTAssertTrue(friendsList.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Alice"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Bob"].exists)

        // Incoming request from the seed data should be visible with an Accept action.
        XCTAssertTrue(app.staticTexts["Charlie"].exists)
        XCTAssertTrue(app.buttons["Accept"].exists)
    }

    @MainActor
    func testAcceptingRequestMovesFriendIntoFriendsList() {
        let app = launchApp()
        app.selectTab("Friends")
        signUp(app)

        app.buttons["Accept"].tap()
        XCTAssertTrue(app.staticTexts["Charlie"].waitForExistence(timeout: 5))
        // Charlie should no longer have an Accept button once they're a friend.
        let acceptButtons = app.buttons.matching(identifier: "Accept")
        XCTAssertEqual(acceptButtons.count, 0)
    }

    @MainActor
    func testPokingFriendLogsActivity() {
        let app = launchApp()
        app.selectTab("Friends")
        signUp(app)

        app.staticTexts["Alice"].tap()
        let sendButton = app.buttons["sendPokeButton"]
        XCTAssertTrue(sendButton.waitForExistence(timeout: 5))
        sendButton.tap()

        // Back out and check the activity log picked up the sent poke.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.staticTexts["Poke activity"].tap()
        let activityList = app.descendants(matching: .any)["pokeActivityList"]
        XCTAssertTrue(activityList.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Alice'")).firstMatch.waitForExistence(timeout: 5))
    }

    /// Regression test for a bug where `friends` (and the sibling request/
    /// activity streams) were single-consumer `AsyncStream`s: once a second
    /// screen subscribed concurrently, it stole updates from the first,
    /// so whichever one lost the race stopped reflecting changes — reported
    /// as "Friends page doesn't refresh" and "the permission switch doesn't
    /// work". Visiting the poke-trigger friend picker (a second subscriber)
    /// before toggling a permission on the Friends tab (the first
    /// subscriber) reproduces the exact interleaving that broke.
    @MainActor
    func testPermissionToggleUpdatesAfterAnotherScreenSubscribesToFriends() {
        let app = launchApp()
        app.selectTab("Friends")
        signUp(app)

        app.selectTab("Settings")
        app.buttons["pokeTriggerSettingsLink"].tap()
        let enableToggle = app.switches["pokeTriggerEnableToggle"]
        XCTAssertTrue(enableToggle.waitForExistence(timeout: 8))
        enableToggle.switches.firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["pokeTriggerFriendPicker"].waitForExistence(timeout: 8))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.selectTab("Friends")
        app.staticTexts["Alice"].tap()
        app.staticTexts["Permissions you've granted Alice"].tap()

        // Seed data: Alice's granted Zap permission starts disabled, so this
        // is the first "Allow" toggle in the form (StimulusKind.allCases
        // order is zap, vibe, beep).
        let zapAllowToggle = app.switches.element(boundBy: 0)
        XCTAssertTrue(zapAllowToggle.waitForExistence(timeout: 8))
        XCTAssertEqual(zapAllowToggle.value as? String, "0")

        zapAllowToggle.switches.firstMatch.tap()

        let becameOn = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: zapAllowToggle)
        wait(for: [becameOn], timeout: 8)

        // The intensity slider only appears once `isAllowed` is true — a
        // second signal, beyond the switch's own value, that the toggle's
        // write actually round-tripped back through the friends stream.
        let intensitySlider = app.sliders["zapIntensitySlider"]
        XCTAssertTrue(intensitySlider.waitForExistence(timeout: 5))
        let intensityValue = app.buttons["zapIntensityValueButton"]
        XCTAssertTrue(intensityValue.waitForExistence(timeout: 5))

        // The slider goes through the exact same `updatePermission` →
        // `refreshFriends` round trip as the "Allow" switch, so it was
        // equally exposed to the stream race — drag it and confirm the
        // displayed value updates too.
        let beforeValue = intensityValue.label
        intensitySlider.adjust(toNormalizedSliderPosition: 0.8)
        let valueUpdated = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label != %@", beforeValue),
            object: intensityValue
        )
        wait(for: [valueUpdated], timeout: 8)
    }

    /// The automation question sits with each allowed stimulus, says what
    /// "Default" currently means, and takes an explicit answer.
    @MainActor
    func testAutomationConsentCanBeAnsweredPerStimulus() {
        let app = launchApp()
        app.selectTab("Friends")
        signUp(app)

        app.staticTexts["Alice"].tap()
        app.staticTexts["Permissions you've granted Alice"].tap()

        // Seed data: vibe is allowed for Alice, zap is not — only vibe asks.
        // Below the fold, and a `Form` only builds rows it shows.
        XCTAssertTrue(app.switches.element(boundBy: 0).waitForExistence(timeout: 8))
        app.swipeUp()
        let vibePicker = app.buttons["vibeAutomationPicker"]
        XCTAssertTrue(vibePicker.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["zapAutomationPicker"].exists)
        XCTAssertTrue(vibePicker.label.contains("Default (allowed)"), vibePicker.label)

        vibePicker.tap()
        app.buttons["Block"].tap()

        let blocked = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "Block"),
            object: vibePicker
        )
        wait(for: [blocked], timeout: 8)
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
