import Foundation

/// Relative timestamps for lists — "5 minutes ago", and it stays that way.
///
/// `Text(date, style: .relative)` re-renders itself every second. In a list of
/// pokes that means a column of counters ticking out of step, which reads as
/// activity where there is none and makes the whole screen impossible to
/// glance at. Nothing in an activity log changes second to second, so the
/// string is computed once per render and left alone; the exact timestamp
/// lives on the detail screen, where it can be read properly.
enum RelativeTime {
    /// Below this the formatter counts individual seconds — exactly the
    /// ticking this type exists to avoid.
    private static let justNowWindow: TimeInterval = 60

    // Formatters are expensive to build and this one is called once per row.
    // Immutable after setup, and only ever read, so sharing it is safe.
    nonisolated(unsafe) private static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        // "yesterday" rather than "1 day ago".
        formatter.dateTimeStyle = .named
        // Pinned rather than taking the device locale: every other string in
        // this app is English, and the system formatter would otherwise put
        // "před 5 minutami" directly under "You zapped Petr". If the app is
        // ever localised, this is the line to drop.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    static func string(for date: Date, now: Date = Date()) -> String {
        let elapsed = now.timeIntervalSince(date)
        if elapsed >= 0, elapsed < justNowWindow { return "just now" }
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
