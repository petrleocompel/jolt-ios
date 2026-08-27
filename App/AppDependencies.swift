import Foundation
import Observation
import SwiftData
import UserNotifications

/// Composition root. Built once in `JoltApp.init` and threaded down through
/// the environment; feature view models take protocol types out of this so
/// they stay swappable (e.g. for previews or tests).
@MainActor
@Observable
final class AppDependencies {
    let deviceRepository: DeviceRepository
    let alarmRepository: AlarmRepository
    let phoneAlarmScheduler: PhoneAlarmScheduler
    let notificationDelegate: AlarmNotificationDelegate
    let modelContainer: ModelContainer

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(for: AlarmEntity.self)
        } catch {
            fatalError("Failed to create SwiftData ModelContainer: \(error)")
        }
        self.modelContainer = container
        self.alarmRepository = SwiftDataAlarmRepository(modelContainer: container)
        self.phoneAlarmScheduler = PhoneAlarmScheduler()
        self.deviceRepository = AppEnvironment.isSnapshotMode
            ? FakeDeviceRepository()
            : CompositeDeviceRepository()
        let delegate = AlarmNotificationDelegate()
        self.notificationDelegate = delegate
        UNUserNotificationCenter.current().delegate = delegate
    }
}
