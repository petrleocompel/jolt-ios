import XCTest

extension XCUIApplication {
    /// Selects a top-level tab by name across device idioms.
    ///
    /// On iPhone the `TabView` renders a classic tab bar, so
    /// `app.tabBars.buttons[name]` works. On iPad (iOS 26) it renders a
    /// floating pill at the *top* instead, which is not a `TabBar` element at
    /// all — the tabs are plain buttons, and each is reported twice (a button
    /// nested inside an identical button). There, `tabBars` matches nothing
    /// ("Failed to tap … No matches found for Descendants matching type
    /// TabBar") and a bare `buttons[name]` is ambiguous.
    ///
    /// So: try the tab bar, then fall back to `.firstMatch` on the button
    /// query.
    @discardableResult
    func selectTab(_ name: String, timeout: TimeInterval = 3) -> Bool {
        let tabBarButton = tabBars.buttons[name]
        if tabBarButton.waitForExistence(timeout: timeout) {
            tabBarButton.tap()
            return true
        }
        let button = buttons[name].firstMatch
        if button.waitForExistence(timeout: timeout) {
            button.tap()
            return true
        }
        return false
    }
}
