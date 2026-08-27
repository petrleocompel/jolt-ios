import Foundation

protocol AlarmRepository {
    func fetchAll() async throws -> [Alarm]
    func save(_ alarm: Alarm) async throws
    func delete(_ id: Alarm.ID) async throws
}
