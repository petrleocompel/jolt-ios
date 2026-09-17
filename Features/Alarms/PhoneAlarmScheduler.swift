import Foundation
import UserNotifications

/// Schedules `AlarmLocation.phone` alarms as local notifications.
///
/// This is the best iOS allows without Apple's Critical Alerts entitlement:
/// a notification with sound can still be silenced by Do Not Disturb, Focus,
/// or the ringer switch, and won't fire at all if the app has been force-
/// quit and the device rebooted. Device alarms (stored on the wearable) do
/// not have these limitations — see README "Known gaps".
struct PhoneAlarmScheduler {
    private let center = UNUserNotificationCenter.current()

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func schedule(_ alarm: Alarm) async throws {
        try await cancel(alarm.id)
        guard alarm.isEnabled else { return }

        let content = Self.makeContent(for: alarm)
        let triggers = makeTriggers(for: alarm)
        for (index, trigger) in triggers.enumerated() {
            let request = UNNotificationRequest(
                identifier: "\(alarm.id.uuidString)#\(index)",
                content: content,
                trigger: trigger
            )
            try await center.add(request)
        }
    }

    /// Rings `alarm` once more `snoozeInterval` from `now`, as a one-off
    /// notification carrying the same content (and so the same `alarmID`),
    /// so tapping it reopens the ringing screen for the same alarm.
    func snooze(_ alarm: Alarm, now: Date = Date()) async throws {
        try await center.add(Self.makeSnoozeRequest(for: alarm, now: now))
    }

    func cancel(_ alarmID: Alarm.ID) async throws {
        let pending = await center.pendingNotificationRequests()
        let identifiers = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(alarmID.uuidString) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    /// The design's "Snooze 9 min" — the classic iOS/Android snooze length.
    static let snoozeInterval: TimeInterval = 9 * 60

    /// Built without touching `UNUserNotificationCenter`, so the snooze
    /// schedule is unit-testable. The identifier keeps the `alarmID` prefix
    /// `cancel(_:)` matches on: deleting, disabling or re-saving the alarm
    /// also drops a pending snooze instead of leaving it to ring an alarm
    /// that no longer exists.
    static func makeSnoozeRequest(for alarm: Alarm, now: Date = Date()) -> UNNotificationRequest {
        let fireDate = snoozeFireDate(from: now)
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, fireDate.timeIntervalSince(now)),
            repeats: false
        )
        return UNNotificationRequest(
            identifier: "\(alarm.id.uuidString)#snooze",
            content: makeContent(for: alarm),
            trigger: trigger
        )
    }

    static func snoozeFireDate(from now: Date) -> Date {
        now.addingTimeInterval(snoozeInterval)
    }

    /// Shared by scheduled and snoozed notifications. `alarmID` in
    /// `userInfo` is what `AppNotificationDelegate` keys the full-screen
    /// ringing flow off.
    static func makeContent(for alarm: Alarm) -> UNNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = alarm.label.isEmpty ? "Jolt Alarm" : alarm.label
        content.body = alarm.dismissChallenge == .none
            ? "Tap to dismiss."
            : "Complete: \(alarm.dismissChallenge.displayName)"
        content.sound = .defaultCritical
        content.userInfo = ["alarmID": alarm.id.uuidString]
        return content
    }

    private func makeTriggers(for alarm: Alarm) -> [UNCalendarNotificationTrigger] {
        if alarm.repeatDays.isEmpty {
            var components = DateComponents()
            components.hour = alarm.hour
            components.minute = alarm.minute
            return [UNCalendarNotificationTrigger(dateMatching: components, repeats: false)]
        }
        return alarm.repeatDays.map { day in
            var components = DateComponents()
            components.hour = alarm.hour
            components.minute = alarm.minute
            components.weekday = day.calendarWeekday
            return UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        }
    }
}

private extension Weekday {
    /// `Calendar` weekday is 1 = Sunday...7 = Saturday; ours is 1 = Monday.
    var calendarWeekday: Int {
        rawValue == Weekday.sunday.rawValue ? 1 : rawValue + 1
    }
}
