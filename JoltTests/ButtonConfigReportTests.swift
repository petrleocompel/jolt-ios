import XCTest
@testable import Jolt

/// The wire-format layer recovered from `pavlok.bin` 6.8.0.
///
/// The length rule is the part worth pinning. The firmware refuses a write
/// whose tail is short and that refusal is invisible in the UI, so a
/// regression here looks like "button config silently does nothing" rather
/// than like a test failure. See `docs/RE-FINDINGS.md` §3.
final class ButtonActionRecordTests: XCTestCase {
    /// Transcribed from the compare-chain at `0x225AC`.
    func testRecordLengthsMatchTheFirmware() {
        let expected: [UInt8: Int] = [
            0x01: 6, 0x02: 6, 0x03: 3, 0x05: 2, 0x0B: 5, 0x0C: 5,
            0x0E: 3, 0x10: 2, 0x11: 4, 0x12: 3, 0xFF: 1
        ]
        for (action, length) in expected {
            XCTAssertEqual(
                ButtonActionRecord.length(forAction: action), length,
                "action 0x\(String(action, radix: 16))"
            )
        }
    }

    /// The chain's own default: anything else at or below `0x12` is one byte.
    func testUnlistedActionsBelowTheCeilingAreOneByte() {
        XCTAssertEqual(ButtonActionRecord.length(forAction: 0x00), 1)
        XCTAssertEqual(ButtonActionRecord.length(forAction: 0x06), 1)
        XCTAssertEqual(ButtonActionRecord.length(forAction: 0x0D), 1)
    }

    func testActionsAboveTheCeilingAreRejected() {
        XCTAssertEqual(ButtonActionRecord.length(forAction: 0x13), 0)
        XCTAssertFalse(ButtonActionRecord.isWritable(action: 0x13))
        XCTAssertEqual(ButtonActionRecord.length(forAction: 0x20), 0)
        XCTAssertTrue(ButtonActionRecord.isWritable(action: 0xFF))
    }

    /// Both are action byte `0x11`; only the tail tells them apart.
    func testStopwatchAndTimerAreDistinguishedByTheirTail() {
        XCTAssertEqual(ButtonActionRecord(bytes: Data([0x11, 0x02, 0x10, 0x01])).action, .stopWatch)
        XCTAssertEqual(ButtonActionRecord(bytes: Data([0x11, 0x02, 0x10, 0x02])).action, .timer)
    }

    /// The firmware's own per-button defaults, read off the table at `0x3E85C`
    /// — the closest thing to a known-good sample we have without hardware.
    func testFirmwareDefaultRecordsDecode() {
        XCTAssertEqual(
            ButtonActionRecord(bytes: Data([0x01, 0x01, 0x02, 0x50, 0x16, 0x16])).action, .vibrate
        )
        XCTAssertEqual(ButtonActionRecord(bytes: Data([0x03, 0x01, 0x1E])).action, .zap)
        XCTAssertEqual(ButtonActionRecord(bytes: Data([0xFF])).action, .disabled)
        XCTAssertEqual(ButtonActionRecord(bytes: Data([0x10, 0x00])).action, .findMyPhone)
    }
}

/// Parsing the burst the device pushes on `7001` after the `01 01` query.
final class ButtonConfigReportTests: XCTestCase {
    func testHeaderThenRecordAttributesTheActionToThatButton() {
        let report = ButtonConfigReport.parse(frames: [
            Data([0xE1, 0x04, 0x01]), Data([0x10, 0x00])
        ])
        XCTAssertEqual(report.actions[.topLong], .findMyPhone)
        XCTAssertTrue(report.unparsed.isEmpty)
    }

    func testEachButtonInABurstKeepsItsOwnRecord() {
        let report = ButtonConfigReport.parse(frames: [
            Data([0xE1, 0x01, 0x01]), Data([0x01, 0x01, 0x02, 0x50, 0x16, 0x16]),
            Data([0xE1, 0x04, 0x01]), Data([0x10, 0x00]),
            Data([0xE1, 0x03, 0x01]), Data([0xFF])
        ])
        XCTAssertEqual(report.actions[.top], .vibrate)
        XCTAssertEqual(report.actions[.topLong], .findMyPhone)
        XCTAssertEqual(report.actions[.bottom], .disabled)
    }

    /// The report machine copies a state byte ahead of the payload
    /// (`0x2F1CC`); whether it reaches the wire isn't pinned down without a
    /// live capture, so the parser has to survive both shapes.
    ///
    /// The leading byte here is `0x99` — deliberately not a valid action —
    /// because the two shapes are only distinguishable when the prefix can't
    /// be read as a record in its own right. See the next test.
    func testARecordCarryingOneLeadingFramingByteStillDecodes() {
        let report = ButtonConfigReport.parse(frames: [
            Data([0xE1, 0x04, 0x01]), Data([0x99, 0x10, 0x00])
        ])
        XCTAssertEqual(report.actions[.topLong], .findMyPhone)
    }

    /// When a frame reads as a valid record on its own, that reading wins,
    /// even though it could also be a framing byte in front of another
    /// record. The ambiguity is real and unresolvable without hardware — this
    /// pins which way it resolves so a live capture can contradict it
    /// deliberately rather than by accident.
    func testAFrameThatIsAlreadyAValidRecordIsNotReinterpreted() {
        let report = ButtonConfigReport.parse(frames: [
            Data([0xE1, 0x04, 0x01]), Data([0x06, 0x10, 0x00])
        ])
        XCTAssertEqual(report.actions[.topLong], .toggleCandle)
    }

    /// The same machine reports timers and other state, under headers whose
    /// second byte isn't a button. Those records must not be mistaken for one.
    func testHeadersOutsideTheButtonRangeStrandTheirRecords() {
        let report = ButtonConfigReport.parse(frames: [
            Data([0xE1, 0x09, 0x01]), Data([0x11, 0x02, 0x10, 0x01])
        ])
        XCTAssertTrue(report.actions.isEmpty)
        XCTAssertEqual(report.unparsed.count, 1)
    }

    /// Whatever the decode makes of them, the frames stay available — they're
    /// the evidence when this disagrees with real hardware.
    func testEveryFrameIsKeptVerbatim() {
        let frames = [Data([0xE1, 0x01, 0x01]), Data([0xFF]), Data([0x99, 0x99])]
        XCTAssertEqual(ButtonConfigReport.parse(frames: frames).frames, frames)
    }

    func testNoFramesMeansAnEmptyReport() {
        let report = ButtonConfigReport.parse(frames: [])
        XCTAssertTrue(report.isEmpty)
        XCTAssertTrue(report.actions.isEmpty)
    }
}
