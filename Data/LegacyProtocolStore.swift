import CoreBluetooth
import Foundation

/// User-correctable parts of the Pavlok 2/3 wire protocol.
///
/// The mapping in `LegacyGATT` is now decompiled ground truth, so an
/// override should never be needed on a stock Pavlok 2/3. It is kept for
/// firmware that turns out to differ, and because it costs nothing — but
/// "reset to defaults" is the right first move if a stimulus misbehaves.
struct LegacyProtocolStore {
    private let defaults: UserDefaults
    private let key = "cz.peelco.jolt.legacyStimulusCharacteristics"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Characteristic to write for `kind`, honouring an override if one has
    /// been set.
    func characteristic(for kind: StimulusKind) -> CBUUID {
        guard let overrides = loadOverrides(), let raw = overrides[kind.rawValue] else {
            return LegacyGATT.characteristic(for: kind)
        }
        return CBUUID(string: raw)
    }

    func hasOverride(for kind: StimulusKind) -> Bool {
        loadOverrides()?[kind.rawValue] != nil
    }

    func setCharacteristic(_ uuid: CBUUID?, for kind: StimulusKind) {
        var overrides = loadOverrides() ?? [:]
        if let uuid {
            overrides[kind.rawValue] = uuid.uuidString
        } else {
            overrides.removeValue(forKey: kind.rawValue)
        }
        guard let data = try? JSONEncoder().encode(overrides) else { return }
        defaults.set(data, forKey: key)
    }

    /// String-shaped accessors so `Features/` can drive the override UI
    /// without importing CoreBluetooth (see `DeviceRepository`'s header on
    /// keeping the UI layer free of BLE types). `CBUUID.uuidString` returns
    /// the 16-bit short form for Bluetooth-base UUIDs, which is also what a
    /// `GATTCharacteristicDump` carries, so the two compare directly.
    func characteristicUUIDString(for kind: StimulusKind) -> String {
        characteristic(for: kind).uuidString
    }

    func setCharacteristicUUIDString(_ uuidString: String?, for kind: StimulusKind) {
        setCharacteristic(uuidString.map { CBUUID(string: $0) }, for: kind)
    }

    func reset() {
        defaults.removeObject(forKey: key)
    }

    private func loadOverrides() -> [String: String]? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode([String: String].self, from: data)
    }
}
