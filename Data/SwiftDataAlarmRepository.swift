import Foundation
import SwiftData

@ModelActor
actor SwiftDataAlarmRepository: AlarmRepository {
    func fetchAll() async throws -> [Alarm] {
        let entities = try modelContext.fetch(FetchDescriptor<AlarmEntity>())
        return entities.compactMap(Alarm.init(entity:))
    }

    func save(_ alarm: Alarm) async throws {
        guard let entity = alarm.makeEntity() else {
            throw EncodingError.invalidValue(alarm, .init(codingPath: [], debugDescription: "Failed to encode stimulus"))
        }
        let id = alarm.id
        let existing = try modelContext.fetch(FetchDescriptor<AlarmEntity>(predicate: #Predicate { $0.id == id }))
        existing.forEach { modelContext.delete($0) }
        modelContext.insert(entity)
        try modelContext.save()
    }

    func delete(_ id: Alarm.ID) async throws {
        let existing = try modelContext.fetch(FetchDescriptor<AlarmEntity>(predicate: #Predicate { $0.id == id }))
        existing.forEach { modelContext.delete($0) }
        try modelContext.save()
    }
}
