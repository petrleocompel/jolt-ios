import Foundation

/// Where an alarm actually fires. Device alarms live on the wearable's own
/// RTC and survive the phone being off or out of range; phone alarms are
/// local notifications and inherit iOS's silencing/Do Not Disturb behaviour
/// (see README "Known gaps").
enum AlarmLocation: String, Codable {
    case device
    case phone
}

struct Alarm: Identifiable, Codable, Equatable {
    var id: UUID
    var location: AlarmLocation
    var hour: Int
    var minute: Int
    var repeatDays: Set<Weekday>
    var isEnabled: Bool
    var label: String
    var stimulus: StimulusConfig
    var dismissChallenge: DismissChallenge

    init(
        id: UUID = UUID(),
        location: AlarmLocation,
        hour: Int,
        minute: Int,
        repeatDays: Set<Weekday> = [],
        isEnabled: Bool = true,
        label: String = "",
        stimulus: StimulusConfig = StimulusConfig(kind: .beep),
        dismissChallenge: DismissChallenge = .none
    ) {
        self.id = id
        self.location = location
        self.hour = hour
        self.minute = minute
        self.repeatDays = repeatDays
        self.isEnabled = isEnabled
        self.label = label
        self.stimulus = stimulus
        self.dismissChallenge = dismissChallenge
    }
}

extension Alarm {
    /// The next real-world moment this alarm will ring, or `nil` when it's
    /// disabled. Used by the Remote dashboard's "Next alarm" card to pick
    /// the single soonest alarm out of however many exist.
    func nextOccurrence(after now: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard isEnabled else { return nil }
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        if repeatDays.isEmpty {
            return calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTimePreservingSmallerComponents)
        }
        return repeatDays.compactMap { day -> Date? in
            var withDay = components
            withDay.weekday = day.calendarWeekday
            return calendar.nextDate(after: now, matching: withDay, matchingPolicy: .nextTimePreservingSmallerComponents)
        }.min()
    }
}

/// `Calendar` weekday is 1 = Sunday...7 = Saturday; ours is 1 = Monday. Same
/// mapping as `PhoneAlarmScheduler`'s private copy — kept local rather than
/// shared since it's a one-line `Calendar` adapter, not domain logic.
private extension Weekday {
    var calendarWeekday: Int {
        rawValue == Weekday.sunday.rawValue ? 1 : rawValue + 1
    }
}

enum Weekday: Int, CaseIterable, Codable, Comparable {
    case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday

    static func < (lhs: Weekday, rhs: Weekday) -> Bool { lhs.rawValue < rhs.rawValue }

    var shortLabel: String {
        switch self {
        case .monday: return "Mon"
        case .tuesday: return "Tue"
        case .wednesday: return "Wed"
        case .thursday: return "Thu"
        case .friday: return "Fri"
        case .saturday: return "Sat"
        case .sunday: return "Sun"
        }
    }
}
