import Foundation
import Observation
import os

/// Everything BLE-related logs through here.
///
/// Two sinks, deliberately: `os.Logger` for Console.app / `log stream` while
/// a device is attached, and an in-memory ring buffer that
/// `DeviceDiagnosticsView` renders and can share. The ring buffer is what
/// makes a "nothing happened when I tapped Zap" report actionable without
/// the user needing Xcode attached.
enum BLELog {
    static let logger = Logger(subsystem: "cz.peelco.jolt", category: "BLE")

    enum Level: String {
        case debug, info, error
    }

    static func debug(_ message: @autoclosure () -> String) { emit(.debug, message()) }
    static func info(_ message: @autoclosure () -> String) { emit(.info, message()) }
    static func error(_ message: @autoclosure () -> String) { emit(.error, message()) }

    private static func emit(_ level: Level, _ message: String) {
        switch level {
        case .debug: logger.debug("\(message, privacy: .public)")
        case .info: logger.info("\(message, privacy: .public)")
        case .error: logger.error("\(message, privacy: .public)")
        }
        Task { @MainActor in BLEEventLog.shared.append(level: level, message: message) }
    }
}

struct BLEEvent: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let level: BLELog.Level
    let message: String

    var formatted: String {
        "\(time)  [\(level.rawValue)] \(message)"
    }

    /// `HH:mm:ss.SSS` — milliseconds matter when lining a write up with its
    /// acknowledgement.
    var time: String {
        BLEEvent.formatter.string(from: timestamp)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}

/// Bounded so a long-running session can't grow without limit; 500 entries is
/// several minutes of connect/scan/write chatter, far more than is needed to
/// see why one button press did nothing. In memory only, so it covers the
/// current launch and nothing before it.
@MainActor
@Observable
final class BLEEventLog {
    static let shared = BLEEventLog()

    private(set) var events: [BLEEvent] = []
    /// Exposed so the log screen can state the real retention instead of a
    /// copy of the number that could drift.
    static let limit = 500

    private init() {}

    func append(level: BLELog.Level, message: String) {
        events.append(BLEEvent(timestamp: .now, level: level, message: message))
        if events.count > Self.limit { events.removeFirst(events.count - Self.limit) }
    }

    func clear() { events.removeAll() }

    /// Oldest first — matches the Bluetooth log screen, and reads as a
    /// sequence (write, then its acknowledgement) when pasted into an issue.
    var transcript: String {
        events.map(\.formatted).joined(separator: "\n")
    }
}

extension BLELog.Level: Equatable {}
