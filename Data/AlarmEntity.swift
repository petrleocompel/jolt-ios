import Foundation
import SwiftData

/// SwiftData persistence model. Kept separate from `Domain.Alarm` so the
/// domain type has no framework dependency; `SwiftDataAlarmRepository`
/// converts between the two.
@Model
final class AlarmEntity {
    @Attribute(.unique) var id: UUID
    var locationRaw: String
    var hour: Int
    var minute: Int
    var repeatDaysRaw: [Int]
    var isEnabled: Bool
    var label: String
    var stimulusData: Data
    var dismissChallengeRaw: String

    init(
        id: UUID,
        locationRaw: String,
        hour: Int,
        minute: Int,
        repeatDaysRaw: [Int],
        isEnabled: Bool,
        label: String,
        stimulusData: Data,
        dismissChallengeRaw: String
    ) {
        self.id = id
        self.locationRaw = locationRaw
        self.hour = hour
        self.minute = minute
        self.repeatDaysRaw = repeatDaysRaw
        self.isEnabled = isEnabled
        self.label = label
        self.stimulusData = stimulusData
        self.dismissChallengeRaw = dismissChallengeRaw
    }
}

extension Alarm {
    init?(entity: AlarmEntity) {
        guard let location = AlarmLocation(rawValue: entity.locationRaw),
              let stimulus = try? JSONDecoder().decode(StimulusConfig.self, from: entity.stimulusData),
              let challenge = DismissChallenge(rawValue: entity.dismissChallengeRaw) else { return nil }
        self.init(
            id: entity.id,
            location: location,
            hour: entity.hour,
            minute: entity.minute,
            repeatDays: Set(entity.repeatDaysRaw.compactMap(Weekday.init(rawValue:))),
            isEnabled: entity.isEnabled,
            label: entity.label,
            stimulus: stimulus,
            dismissChallenge: challenge
        )
    }

    func makeEntity() -> AlarmEntity? {
        guard let stimulusData = try? JSONEncoder().encode(stimulus) else { return nil }
        return AlarmEntity(
            id: id,
            locationRaw: location.rawValue,
            hour: hour,
            minute: minute,
            repeatDaysRaw: repeatDays.map(\.rawValue),
            isEnabled: isEnabled,
            label: label,
            stimulusData: stimulusData,
            dismissChallengeRaw: dismissChallenge.rawValue
        )
    }
}
