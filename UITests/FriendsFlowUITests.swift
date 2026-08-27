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
        app.tabBars.buttons["Friends"].tap()

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
        app.tabBars.buttons["Friends"].tap()
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
        app.tabBars.buttons["Friends"].tap()
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
