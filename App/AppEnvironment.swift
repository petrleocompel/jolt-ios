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

    /// Use `FakeDeviceRepository` (an always-connected stand-in) instead of
    /// real BLE. Snapshot runs always do; UI tests opt in so the tab bar —
    /// which `RootView` only shows once a device is connected — is reachable
    /// in a simulator that has no wearable. Deliberately separate from
    /// `isSnapshotMode` so a test can fake the *device* while still talking
    /// to a real server.
    static let usesFakeDevice: Bool = {
        isSnapshotMode || ProcessInfo.processInfo.arguments.contains("-fakeDevice")
    }()

    /// Wipe `UserDefaults`-backed settings at launch. Snapshot runs always do
    /// this (hermetic screenshots); UI tests that talk to a real server opt in
    /// explicitly, so a quick-poke target left behind by an earlier run can't
    /// decide the next run's outcome.
    static let shouldResetPersistedState: Bool = {
        isSnapshotMode || ProcessInfo.processInfo.arguments.contains("-resetPersistedState")
    }()
}
