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
        let time = BLEEvent.formatter.string(from: timestamp)
        return "\(time)  [\(level.rawValue)] \(message)"
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}

/// Bounded so a long-running session can't grow without limit; 500 entries is
/// several minutes of connect/scan/write chatter, far more than is needed to
/// see why one button press did nothing.
@MainActor
@Observable
final class BLEEventLog {
    static let shared = BLEEventLog()

    private(set) var events: [BLEEvent] = []
    private let limit = 500

    private init() {}

    func append(level: BLELog.Level, message: String) {
        events.append(BLEEvent(timestamp: .now, level: level, message: message))
        if events.count > limit { events.removeFirst(events.count - limit) }
    }

    func clear() { events.removeAll() }

    /// Newest first — matches how the diagnostics list renders it, and how
    /// someone reading a pasted log wants to see it.
    var transcript: String {
        events.reversed().map(\.formatted).joined(separator: "\n")
    }
}

extension BLELog.Level: Equatable {}
