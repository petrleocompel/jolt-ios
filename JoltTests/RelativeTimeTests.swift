import XCTest
@testable import Jolt

final class RelativeTimeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// The whole point: under a minute the system formatter counts seconds,
    /// which is what made the activity list tick.
    func testCollapsesTheLastMinuteToOneStableString() {
        XCTAssertEqual(RelativeTime.string(for: now, now: now), "just now")
        XCTAssertEqual(RelativeTime.string(for: now.addingTimeInterval(-1), now: now), "just now")
        XCTAssertEqual(RelativeTime.string(for: now.addingTimeInterval(-59), now: now), "just now")
    }

    func testCountsInMinutesAndHoursBeyondThat() {
        XCTAssertEqual(RelativeTime.string(for: now.addingTimeInterval(-5 * 60), now: now), "5 minutes ago")
        XCTAssertEqual(RelativeTime.string(for: now.addingTimeInterval(-60 * 60), now: now), "1 hour ago")
    }

    /// Two renders a second apart must agree, or the list ticks again.
    func testIsStableAcrossASecond() {
        let poke = now.addingTimeInterval(-5 * 60)
        XCTAssertEqual(
            RelativeTime.string(for: poke, now: now),
            RelativeTime.string(for: poke, now: now.addingTimeInterval(1))
        )
    }
}
