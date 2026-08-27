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

        let content = UNMutableNotificationContent()
        content.title = alarm.label.isEmpty ? "Jolt Alarm" : alarm.label
        content.body = alarm.dismissChallenge == .none
            ? "Tap to dismiss."
            : "Complete: \(alarm.dismissChallenge.displayName)"
        content.sound = .defaultCritical
        content.userInfo = ["alarmID": alarm.id.uuidString]

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

    func cancel(_ alarmID: Alarm.ID) async throws {
        let pending = await center.pendingNotificationRequests()
        let identifiers = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(alarmID.uuidString) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
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
