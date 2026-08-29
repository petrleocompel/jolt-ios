import Foundation
import Observation

@MainActor
@Observable
final class AlarmsViewModel {
    private let alarmRepository: AlarmRepository
    private let deviceRepository: DeviceRepository
    private let phoneAlarmScheduler: PhoneAlarmScheduler

    private(set) var alarms: [Alarm] = []
    var lastError: String?

    init(alarmRepository: AlarmRepository, deviceRepository: DeviceRepository, phoneAlarmScheduler: PhoneAlarmScheduler) {
        self.alarmRepository = alarmRepository
        self.deviceRepository = deviceRepository
        self.phoneAlarmScheduler = phoneAlarmScheduler
    }

    func load() async {
        do {
            alarms = try await alarmRepository.fetchAll()
                .sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func save(_ alarm: Alarm) async {
        do {
            try await alarmRepository.save(alarm)
            switch alarm.location {
            case .phone:
                _ = try? await phoneAlarmScheduler.requestAuthorization()
                try await phoneAlarmScheduler.schedule(alarm)
            case .device:
                try await deviceRepository.syncDeviceAlarm(alarm)
            }
            await load()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func delete(_ alarm: Alarm) async {
        do {
            try await alarmRepository.delete(alarm.id)
            switch alarm.location {
            case .phone:
                try await phoneAlarmScheduler.cancel(alarm.id)
            case .device:
                try await deviceRepository.deleteDeviceAlarm(alarm.id)
            }
            await load()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func toggle(_ alarm: Alarm) async {
        var updated = alarm
        updated.isEnabled.toggle()
        await save(updated)
    }
}
