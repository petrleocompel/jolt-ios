import CoreBluetooth
import Foundation

// MARK: - Timeouts
//
// In an extension only to keep the type's body a readable length.
extension BluetoothCentralManager {
    /// Races `operation` against a timer. `onTimeout` is responsible for
    /// resuming whichever continuation `operation` is parked on — without it
    /// a lost CoreBluetooth callback leaks the task forever, which is
    /// exactly how a tap on "Zap" can produce no result and no error.
    func withTimeout(
        _ duration: Duration,
        description: String,
        operation: @escaping () async throws -> Void,
        onTimeout: @escaping @MainActor () -> Void
    ) async throws {
        let timeoutTask = Task { @MainActor in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            BLELog.error("Timed out: \(description)")
            onTimeout()
        }
        defer { timeoutTask.cancel() }
        try await operation()
    }

    func withTimeout<T>(
        _ duration: Duration,
        description: String,
        operation: @escaping () async throws -> T,
        onTimeout: @escaping @MainActor () -> Void
    ) async throws -> T {
        let timeoutTask = Task { @MainActor in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            BLELog.error("Timed out: \(description)")
            onTimeout()
        }
        defer { timeoutTask.cancel() }
        return try await operation()
    }
}
