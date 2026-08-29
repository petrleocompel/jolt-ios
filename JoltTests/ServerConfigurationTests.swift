import XCTest
@testable import Jolt

final class ServerConfigurationTests: XCTestCase {
    func testDefaultPointsAtTheHostedInstanceIncludingApiPath() {
        XCTAssertEqual(ServerConfiguration.default.baseURL.absoluteString, "https://jolt.example.com/api/v1")
    }

    func testAcceptsASelfHostedURL() throws {
        let config = try ServerConfiguration.parse("https://jolt.example.com/api/v1").get()
        XCTAssertEqual(config.baseURL.absoluteString, "https://jolt.example.com/api/v1")
    }

    func testTrimsWhitespaceAndTrailingSlash() throws {
        // A trailing slash would produce `//friends` once paths are appended.
        let config = try ServerConfiguration.parse("  https://jolt.example.com/api/v1/  ").get()
        XCTAssertEqual(config.baseURL.absoluteString, "https://jolt.example.com/api/v1")
    }

    func testRejectsPlainHTTPWithAnExplanation() {
        // ATS blocks it, and the resulting runtime error is unreadable.
        guard case .failure(let error) = ServerConfiguration.parse("http://jolt.example.com/api/v1") else {
            return XCTFail("plain http should be rejected")
        }
        XCTAssertEqual(error, .insecureScheme)
        XCTAssertTrue(error.localizedDescription.contains("https://"))
    }

    func testRejectsEmptyAndMalformedInput() {
        XCTAssertEqual(ServerConfiguration.parse("").failureError, .empty)
        XCTAssertEqual(ServerConfiguration.parse("   ").failureError, .empty)
        XCTAssertEqual(ServerConfiguration.parse("not a url").failureError, .malformed)
        XCTAssertEqual(ServerConfiguration.parse("https://").failureError, .malformed)
    }

    func testAcceptsAPortAndANonStandardBasePath() throws {
        // Someone reverse-proxying Jolt under a subpath is a supported setup.
        let config = try ServerConfiguration.parse("https://home.example.com:8443/jolt/api/v1").get()
        XCTAssertEqual(config.baseURL.host(), "home.example.com")
        XCTAssertEqual(config.baseURL.port, 8443)
        XCTAssertEqual(config.baseURL.path(), "/jolt/api/v1")
    }
}

final class ServerSettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "ServerSettingsStoreTests-\(UUID().uuidString)")
    }

    func testDefaultsToTheHostedInstance() {
        let store = ServerSettingsStore(defaults: defaults)
        XCTAssertEqual(store.load(), .default)
        XCTAssertFalse(store.isCustom)
    }

    func testCustomServerSurvivesAReload() throws {
        let store = ServerSettingsStore(defaults: defaults)
        let custom = try ServerConfiguration.parse("https://jolt.example.com/api/v1").get()
        store.save(custom)

        XCTAssertEqual(ServerSettingsStore(defaults: defaults).load(), custom)
        XCTAssertTrue(store.isCustom)
    }

    func testResetReturnsToTheDefault() throws {
        let store = ServerSettingsStore(defaults: defaults)
        store.save(try ServerConfiguration.parse("https://jolt.example.com/api/v1").get())
        store.reset()
        XCTAssertEqual(store.load(), .default)
        XCTAssertFalse(store.isCustom)
    }
}

private extension Result where Success == ServerConfiguration, Failure == ServerConfiguration.ValidationError {
    var failureError: ServerConfiguration.ValidationError? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
