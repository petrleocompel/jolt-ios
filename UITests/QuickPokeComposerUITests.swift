import XCTest

/// Reproduces the reported bug: with a quick-poke friend configured on the
/// Remote dashboard, the card's "⋯" button opened a sheet that said "Friend
/// not found" even though that friend was plainly visible on the Friends tab.
///
/// Runs against a **real Jolt Server** (no `-snapshotMode`), because the bug
/// never reproduced against `MockSocialBackend` — the difference is exactly
/// what's under test. Requires the server in `ServerConfiguration.default`
/// to be reachable and the README's test account to exist on it with at
/// least one friend.
final class QuickPokeComposerUITests: XCTestCase {
    private enum TestAccount {
        static let email = "tester@example.com"
        static let password = "REDACTED"
    }

    /// Mirrors `ServerConfiguration.default`. Hardcoded because a UI-test
    /// bundle runs out-of-process and can't import the app's types.
    private static let serverProbeURL = URL(string: "https://jolt.example.com/api/v1/me")!

    override func setUpWithError() throws {
        continueAfterFailure = false
        try skipUnlessServerReachable()
    }

    /// This is a live-server test: it needs the configured Jolt Server and the
    /// README's test account. Skip — rather than fail — where neither exists,
    /// so an unreachable server on a CI runner doesn't read as a code defect.
    private func skipUnlessServerReachable() throws {
        var request = URLRequest(url: Self.serverProbeURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 8

        var reachable = false
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { _, response, _ in
            reachable = response != nil
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 12)

        if !reachable {
            throw XCTSkip("Jolt server at \(Self.serverProbeURL.host() ?? "?") is unreachable.")
        }
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        // No -snapshotMode: this must exercise HTTPSocialBackend against a
        // real server. `-fakeDevice` only stands in for the wearable, so the
        // tab bar is reachable; `-resetPersistedState` keeps a quick-poke
        // target from a previous run out of the way.
        app.launchArguments += ["-fakeDevice", "-resetPersistedState"]
        app.launch()
        return app
    }

    /// The end-to-end path the bug report describes: pick the friend in
    /// Quick Poke settings, then open the dashboard card's composer.
    @MainActor
    func testQuickPokeComposerResolvesConfiguredFriend() throws {
        let app = launchApp()

        let friendName = try signInAndReadFirstFriendName(app)
        try configureQuickPoke(app, friendName: friendName)

        app.selectTab("Remote")

        let composerButton = app.buttons["quickPokeComposerButton"]
        XCTAssertTrue(
            composerButton.waitForExistence(timeout: 10),
            "Quick poke card should be on the dashboard once a friend is configured"
        )
        composerButton.tap()

        // The actual regression: this must resolve to the composer, never to
        // the "Friend not found" state, for a friend that demonstrably exists.
        let composer = app.descendants(matching: .any)["quickPokeComposerSheet"]
        let notFound = app.descendants(matching: .any)["quickPokeFriendNotFound"]

        let settled = NSPredicate { _, _ in composer.exists || notFound.exists }
        wait(for: [expectation(for: settled, evaluatedWith: app)], timeout: 25)

        XCTAssertFalse(notFound.exists, "Composer showed \"Friend not found\" for a friend that exists")
        XCTAssertTrue(composer.exists, "Composer never appeared")
        XCTAssertTrue(
            app.buttons["sendPokeButton"].waitForExistence(timeout: 10),
            "Composer should offer the same full poke controls as the Friends tab"
        )
    }

    // MARK: - Steps

    /// Signs in if needed and returns the display name of the first friend on
    /// the account, failing the test if the account has none.
    @MainActor
    private func signInAndReadFirstFriendName(_ app: XCUIApplication) throws -> String {
        app.selectTab("Friends")

        let emailField = app.textFields["emailField"]
        if emailField.waitForExistence(timeout: 10) {
            emailField.tap()
            emailField.typeText(TestAccount.email)
            let password = app.secureTextFields["passwordField"]
            password.tap()
            password.typeText(TestAccount.password)
            app.buttons["authSubmitButton"].tap()
        }

        let friendsList = app.descendants(matching: .any)["friendsList"]
        XCTAssertTrue(
            friendsList.waitForExistence(timeout: 30),
            "Friends list never appeared — is the server reachable and the test account valid?"
        )

        // The friend rows are the cells under the "Friends" section; the
        // account is expected to have exactly one.
        let friendCell = app.cells.containing(
            NSPredicate(format: "label CONTAINS %@", "can send:")
        ).firstMatch
        XCTAssertTrue(friendCell.waitForExistence(timeout: 20), "Test account should have at least one friend")

        // Row label is "<display name>, @<handle> · can send: …" — the
        // display name is the leading static text.
        let name = friendCell.staticTexts.firstMatch.label
        XCTAssertFalse(name.isEmpty, "Could not read the friend's display name")
        return name
    }

    @MainActor
    private func configureQuickPoke(_ app: XCUIApplication, friendName: String) throws {
        XCTAssertTrue(app.selectTab("Settings", timeout: 10), "Could not select the Settings tab")
        let link = app.descendants(matching: .any)["quickPokeSettingsLink"].firstMatch
        XCTAssertTrue(scrollToElement(link, in: app), "Quick poke settings link never became reachable")
        link.tap()

        let enableToggle = app.switches["quickPokeEnableToggle"]
        XCTAssertTrue(enableToggle.waitForExistence(timeout: 10))
        if enableToggle.value as? String != "1" {
            enableToggle.switches.firstMatch.tap()
        }

        let picker = app.descendants(matching: .any)["quickPokeFriendPicker"]
        XCTAssertTrue(
            picker.waitForExistence(timeout: 20),
            "Friend picker missing — the settings screen never received the friends list"
        )
        picker.tap()

        let option = app.buttons[friendName].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 10), "Friend \(friendName) not offered in the picker")
        option.tap()

        // Back out to the settings root so the tab switch lands cleanly.
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    /// Waits for `element`, swiping up if it hasn't rendered yet — list rows
    /// below the fold don't exist in the hierarchy until scrolled near.
    @MainActor
    private func scrollToElement(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maxSwipes: Int = 6
    ) -> Bool {
        if element.waitForExistence(timeout: 5), element.isHittable { return true }
        for _ in 0..<maxSwipes {
            if element.exists, element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }
}
