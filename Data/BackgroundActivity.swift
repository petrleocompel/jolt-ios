import UIKit

/// Keeps the app running long enough for a request that has already left to
/// finish.
///
/// Without it, locking the screen right after "Tap to poke" suspends the app
/// mid-request: the poke may or may not reach the server, and the answer
/// never comes back. iOS grants a short extension to work that asks for one —
/// this asks.
@MainActor
enum BackgroundActivity {
    static func run<T>(_ name: String, _ work: () async throws -> T) async rethrows -> T {
        let application = UIApplication.shared
        var task = UIBackgroundTaskIdentifier.invalid
        task = application.beginBackgroundTask(withName: name) {
            // Out of time: iOS suspends us either way, and ending the task is
            // what it asks for in return.
            application.endBackgroundTask(task)
            task = .invalid
        }
        defer {
            if task != .invalid { application.endBackgroundTask(task) }
        }
        return try await work()
    }
}
