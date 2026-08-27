import Foundation

struct PairedDeviceRecord: Codable, Equatable {
    var peripheralIdentifier: UUID
    var name: String
    var family: DeviceFamily
}

/// Remembers which device to reconnect to across launches. Deliberately
/// tiny (one device, `UserDefaults`) — matches the current one-device-at-a-
/// time `CompositeDeviceRepository` design; revisit if multi-device pairing
/// is ever needed.
struct PairedDeviceStore {
    private let defaults: UserDefaults
    private let key = "cz.peelco.jolt.pairedDevice"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> PairedDeviceRecord? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(PairedDeviceRecord.self, from: data)
    }

    func save(peripheralIdentifier: UUID, name: String, family: DeviceFamily) {
        let record = PairedDeviceRecord(peripheralIdentifier: peripheralIdentifier, name: name, family: family)
        guard let data = try? JSONEncoder().encode(record) else { return }
        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
