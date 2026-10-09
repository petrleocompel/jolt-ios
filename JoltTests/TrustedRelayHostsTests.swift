import XCTest
@testable import Jolt

/// A self-hosted server names its relay, but only relays on the build's own
/// list ever see this phone's APNs token.
final class TrustedRelayHostsTests: XCTestCase {
    private let trusted = TrustedRelayHosts(infoValue: "relay.example, Second.Example\nthird.example")

    func testParsesSpaceCommaAndNewlineSeparatedHostsCaseInsensitively() {
        XCTAssertEqual(trusted.hosts, ["relay.example", "second.example", "third.example"])
        XCTAssertTrue(trusted.allows(URL(string: "https://RELAY.example/")!))
        XCTAssertTrue(trusted.allows(URL(string: "https://second.example")!))
    }

    func testAllowsAListedHostOverHTTPSOnTheDefaultPort() {
        XCTAssertTrue(trusted.allows(URL(string: "https://relay.example/")!))
        XCTAssertTrue(trusted.allows(URL(string: "https://relay.example:443/v1")!))
    }

    func testRefusesAnythingElse() {
        let refused = [
            "http://relay.example/",
            "https://relay.example:8443/",
            "https://evil.relay.example/",
            "https://relay.example.evil.example/",
            "https://user:pass@relay.example/",
            "https://user@relay.example/",
            "https://other.example/",
            "wss://relay.example/"
        ]
        for string in refused {
            XCTAssertFalse(trusted.allows(URL(string: string)!), string)
        }
    }

    /// A build from source names no relay, and must trust none — not
    /// everything.
    func testAnEmptyOrUnsetListTrustsNothing() {
        for value: Any? in ["", "   ", nil, 42, "$(JOLT_TRUSTED_RELAY_HOSTS)"] {
            let hosts = TrustedRelayHosts(infoValue: value)
            XCTAssertTrue(hosts.hosts.isEmpty, String(describing: value))
            XCTAssertFalse(hosts.allows(URL(string: "https://relay.example/")!))
        }
    }
}
