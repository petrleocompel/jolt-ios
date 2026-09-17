import Foundation

/// Runtime flags that change app behaviour for automated App Store
/// screenshots. See docs/RE-FINDINGS.md screenshot contract and
/// `UITests/ScreenshotsUITests.swift`.
enum AppEnvironment {
    static let isSnapshotMode: Bool = {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-snapshotMode") || arguments.contains("--snapshotMode") {
            return true
        }
        return ProcessInfo.processInfo.environment["SNAPSHOT_MODE"] == "1"
    }()

    /// Use `FakeDeviceRepository` (a stand-in wearable) instead of real BLE.
    /// Snapshot runs always do; UI tests opt in so a connected device is
    /// there to fire at in a simulator that has no Bluetooth. Deliberately
    /// separate from `isSnapshotMode` so a test can fake the *device* while
    /// still talking to a real server.
    static let usesFakeDevice: Bool = {
        isSnapshotMode || startsWithoutDevice || fakeDeviceLinkState != nil
            || ProcessInfo.processInfo.arguments.contains("-fakeDevice")
    }()

    /// Launch as if no wearable has ever been paired — the state a user is in
    /// before, or instead of, owning one. Pairs with `-resetPersistedState`
    /// to exercise the first-run pairing offer and the device-free poke path
    /// hermetically, without a simulator's absent Bluetooth stack deciding
    /// the outcome.
    static let startsWithoutDevice: Bool = {
        ProcessInfo.processInfo.arguments.contains("-noDevice")
    }()

    /// `-ringAlarm` (snapshot mode only): open the seeded "Wake up" alarm's
    /// ringing screen at launch, so the alarm and challenge screens can be
    /// screenshotted without waiting for a notification.
    static let ringsDemoAlarm: Bool = {
        isSnapshotMode && ProcessInfo.processInfo.arguments.contains("-ringAlarm")
    }()

    /// `-fakeDeviceLink offline|connecting|failed`: the fake wearable is
    /// paired but not connected, so the device card's unreachable states can
    /// be screenshotted and tested without real radio conditions.
    static let fakeDeviceLinkState: DeviceConnectionState? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-fakeDeviceLink"), arguments.indices.contains(index + 1) else {
            return nil
        }
        switch arguments[index + 1] {
        case "offline": return .disconnected
        case "connecting": return .connecting
        case "failed": return .failed("Device did not respond")
        default: return nil
        }
    }()

    /// Wipe `UserDefaults`-backed settings at launch. Snapshot runs always do
    /// this (hermetic screenshots); UI tests that talk to a real server opt in
    /// explicitly, so a quick-poke target left behind by an earlier run can't
    /// decide the next run's outcome.
    static let shouldResetPersistedState: Bool = {
        isSnapshotMode || ProcessInfo.processInfo.arguments.contains("-resetPersistedState")
    }()
}
