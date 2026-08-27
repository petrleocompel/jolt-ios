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
}
