import XCTest

// Screen walks and helpers for `DesignReferenceUITests`, kept out of the
// class body so each test reads as the list of screens it captures.

extension DesignReferenceUITests {
    // MARK: - Launch

    @MainActor
    func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        setupSnapshot(app)
        app.launchArguments += ["-snapshotMode", "1"]
        app.launch()
        return app
    }

    // MARK: - Friends walk steps

    /// Add friend, profile, activity, and both friend details.
    @MainActor
    func captureFriendScreens(_ app: XCUIApplication) {
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
    }

    /// Quick poke + poke trigger only have content once there are friends.
    @MainActor
    func captureQuickPokeAndTriggerSettings(_ app: XCUIApplication) {
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
    }

    /// The Remote card and composer for the quick poke configured above.
    @MainActor
    func captureRemoteQuickPoke(_ app: XCUIApplication) {
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

    /// Quick poke still pointing at a friend who's been removed.
    @MainActor
    func captureComposerForRemovedFriend(_ app: XCUIApplication) {
        app.selectTab("Friends")
        if tap(app.staticTexts["Alice"], in: app), tap(app.buttons["Remove friend"], in: app) {
            if app.alerts.buttons["Remove"].waitForExistence(timeout: 2) { app.alerts.buttons["Remove"].tap() }
            app.selectTab("Remote")
            if tap(app.buttons["quickPokeComposerButton"], in: app) {
                _ = element("quickPokeFriendNotFound", in: app).waitForExistence(timeout: 10)
                snapshot("37-Remote-QuickPokeComposer-NotFound")
                tap(app.buttons["Close"].firstMatch, in: app)
            }
        }
    }

    // MARK: - Helpers

    @MainActor
    func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    /// Scrolls to and taps `element`; returns false instead of failing when it
    /// never shows up. Lists are lazy — an off-screen row isn't in the
    /// hierarchy at all — so this scrolls until it exists *and* is hittable,
    /// down first, then back up in case an earlier page left us scrolled past.
    @MainActor
    @discardableResult
    func tap(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
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
    func back(_ app: XCUIApplication) {
        let button = app.navigationBars.buttons.element(boundBy: 0)
        if button.waitForExistence(timeout: 3) { button.tap() }
    }

    @MainActor
    func signUp(_ app: XCUIApplication) {
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
