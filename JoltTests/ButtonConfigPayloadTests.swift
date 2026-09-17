import XCTest
@testable import Jolt

/// The `setButtonAction` payloads, byte for byte.
///
/// These exist because the length is load-bearing and invisible: the firmware
/// looks the action byte up in a length table and refuses the write if fewer
/// bytes follow, so a payload one byte short is rejected with an ATT error and
/// the button silently keeps its old action. Byte values and lengths here are
/// cross-checked against the Android app's `setButtonAction` and the
/// firmware's own parser — see `docs/RE-FINDINGS.md` §3.
final class ButtonConfigPayloadTests: XCTestCase {
    private func payload(_ action: ButtonAction, _ slot: DeviceButtonSlot = .topLong) -> [UInt8]? {
        action.payload(for: slot).map { Array($0) }
    }

    /// The one that matters: `findMyPhone` takes a trailing `00`. Written as
    /// three bytes the device rejects it, which is exactly how the
    /// device-triggered poke came to do nothing at all.
    func testFindMyPhoneCarriesItsTrailingByte() {
        XCTAssertEqual(payload(.findMyPhone), [0x02, 0x04, 0x10, 0x00])
    }

    func testEachWritableActionHasTheLengthTheFirmwareExpects() {
        XCTAssertEqual(payload(.disabled), [0x02, 0x04, 0xFF])
        XCTAssertEqual(payload(.toggleCandle), [0x02, 0x04, 0x06])
        XCTAssertEqual(payload(.nextTune), [0x02, 0x04, 0x07])
        XCTAssertEqual(payload(.stopWatch), [0x02, 0x04, 0x11, 0x02, 0x10, 0x01])
        XCTAssertEqual(payload(.timer), [0x02, 0x04, 0x11, 0x02, 0x10, 0x02])
        XCTAssertEqual(payload(.toggleSleepTracking), [0x02, 0x04, 0x13, 0x01, 0x02])
    }

    func testTheButtonByteIsTheSecondByte() {
        XCTAssertEqual(payload(.findMyPhone, .top)?[1], 0x01)
        XCTAssertEqual(payload(.findMyPhone, .middle)?[1], 0x02)
        XCTAssertEqual(payload(.findMyPhone, .bottom)?[1], 0x03)
        XCTAssertEqual(payload(.findMyPhone, .topLong)?[1], 0x04)
        XCTAssertEqual(payload(.findMyPhone, .middleLong)?[1], 0x05)
        XCTAssertEqual(payload(.findMyPhone, .bottomLong)?[1], 0x06)
    }

    /// Stimulus actions carry a count and an intensity, and a guessed payload
    /// there fires a real shock — so they stay unwritable until traced.
    func testStimulusActionsAreRefusedRatherThanGuessed() {
        XCTAssertNil(payload(.zap))
        XCTAssertNil(payload(.beep))
        XCTAssertNil(payload(.vibrate))
    }

    /// The Android app's own `setButtonAction` falls through to "unsupported"
    /// for these, so there is nothing to copy.
    func testUntracedPhoneActionsAreRefused() {
        XCTAssertNil(payload(.airplaneMode))
        XCTAssertNil(payload(.doNotDisturb))
    }

    /// Action byte `0x00` is not "no action": `set_action` reads it as
    /// *restore this button's firmware default*, copying the record from the
    /// default table at `0x3E85C` instead of from the payload. That's why it
    /// needs no tail and why three bytes is the whole write.
    func testDeviceDefaultRestoresTheFirmwareRecord() {
        XCTAssertEqual(payload(.defaultAction), [0x02, 0x04, 0x00])
    }
}
