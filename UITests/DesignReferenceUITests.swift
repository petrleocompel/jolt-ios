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
            app.swipeUp()
            snapshot("04b-Remote-DeviceDetail-Bottom")
            if tap(app.buttons.matching(NSPredicate(format: "label CONTAINS 'diagnostics'")).firstMatch, in: app) {
                snapshot("05-Remote-Diagnostics")
                app.swipeUp()
                app.swipeUp()
                snapshot("05b-Remote-Diagnostics-Bottom")
                back(app)
            }
            if tap(app.buttons["Button configuration"], in: app) {
                snapshot("06-Remote-ButtonConfig")
                back(app)
            }
            if tap(app.buttons["Protocol lab"], in: app) {
                sleep(1)
                snapshot("07-Remote-ProtocolLab")
                back(app)
            }
            if tap(app.buttons["Bluetooth log"], in: app) {
                snapshot("08-Remote-BluetoothLog")
                back(app)
            }
        }
    }

    /// Firing modes change what a tap on the Remote does; Confirm is the one
    /// with its own screen state.
    @MainActor
    func test01bConfirmBeforeFiring() {
        let app = launchApp()
        app.selectTab("Settings")
        guard tap(element("firingModesSettingsLink", in: app), in: app),
              tap(element("firingModePicker_zap", in: app), in: app),
              app.buttons["Confirm dialog"].firstMatch.waitForExistence(timeout: 3) else { return }
        // A menu: tap directly — the scrolling in `tap` would dismiss it.
        app.buttons["Confirm dialog"].firstMatch.tap()
        back(app)
        app.selectTab("Remote")
        if tap(element("fireButton_zap", in: app), in: app) {
            snapshot("09-Remote-ConfirmFire")
            tap(app.alerts.buttons["Cancel"], in: app)
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

        captureFriendScreens(app)
        captureQuickPokeAndTriggerSettings(app)
        captureRemoteQuickPoke(app)
        captureComposerForRemovedFriend(app)
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
            // The mock backend answers a test push, so the "arrived" state is
            // reachable without a real APNs round trip.
            if page.id == "notificationTestLink", tap(element("sendTestNotificationButton", in: app), in: app) {
                sleep(3)
                snapshot("44b-Settings-Notifications-Arrived")
            }
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

        guard app.buttons["continueWithoutDeviceButton"].waitForExistence(timeout: 10) else { return }
        snapshot("00-FirstRun")

        if tap(app.buttons["pairDeviceButton"], in: app),
           app.buttons["toggleScanButton"].waitForExistence(timeout: 5) {
            snapshot("52-PairDevice")
            app.buttons["toggleScanButton"].tap()
            _ = element("discoveredDevice_pavlok-3", in: app).waitForExistence(timeout: 5)
            snapshot("52c-PairDevice-Found")
            app.buttons["toggleScanButton"].tap()
            tap(app.buttons["Not now"], in: app)
        }

        guard tap(app.buttons["continueWithoutDeviceButton"], in: app) else { return }
        if element("remoteControlScreen", in: app).waitForExistence(timeout: 5) {
            snapshot("01b-Remote-NoDevice")
            if tap(element("fireButton_zap", in: app), in: app) {
                _ = element("errorFeedback", in: app).waitForExistence(timeout: 3)
                snapshot("09c-Remote-NoDeviceFireBanner")
            }
        }

        app.selectTab("Settings")
        snapshot("40b-Settings-NoDevice")
    }

    /// A paired device that isn't connected: out of range, reconnecting, or
    /// a connection that failed. `-fakeDeviceLink` starts the fake wearable
    /// in each state.
    @MainActor
    func test06DeviceLinkStates() {
        let states: [(argument: String, name: String)] = [
            ("offline", "01c-Remote-OutOfRange"),
            ("connecting", "01d-Remote-Connecting"),
            ("failed", "01e-Remote-ConnectFailed")
        ]
        for state in states {
            let app = XCUIApplication()
            setupSnapshot(app)
            app.launchArguments += ["-snapshotMode", "1", "-fakeDeviceLink", state.argument]
            app.launch()
            guard element("remoteControlScreen", in: app).waitForExistence(timeout: 10) else { continue }
            snapshot(state.name)
            if state.argument == "offline" {
                app.selectTab("Settings")
                snapshot("40c-Settings-OutOfRange")
            }
            app.terminate()
        }
    }

    // MARK: - Ringing alarm

    /// `-ringAlarm` opens the seeded "Wake up" alarm (QR challenge) as if its
    /// notification had fired; switching challenges reaches the other two.
    @MainActor
    func test07RingingAlarm() {
        let app = XCUIApplication()
        setupSnapshot(app)
        app.launchArguments += ["-snapshotMode", "1", "-ringAlarm"]
        app.launch()

        guard element("ringingAlarmTime", in: app).waitForExistence(timeout: 10) else { return }
        snapshot("14-Alarms-Ringing")
        guard tap(app.buttons["dismissAlarmButton"], in: app) else { return }

        if element("qrCodeChallengeScreen", in: app).waitForExistence(timeout: 5) {
            sleep(1)
            snapshot("17-Alarms-ChallengeQR")
        }
        if tap(app.buttons["switchChallengeButton"], in: app),
           tap(app.buttons["Use a math puzzle instead"].firstMatch, in: app),
           element("mathPuzzleQuestion", in: app).waitForExistence(timeout: 5) {
            snapshot("15-Alarms-ChallengeMath")
            if tap(app.buttons["Use jumping jacks instead"], in: app),
               element("jumpingJacksCount", in: app).waitForExistence(timeout: 5) {
                snapshot("16-Alarms-ChallengeJacks")
            }
        }
    }
}
