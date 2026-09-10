import CoreBluetooth

/// The per-device-family operations `CompositeDeviceRepository` dispatches to
/// `LegacyDeviceController` or `SCMaxDeviceController`. Both already implement
/// this shape; this just gives `CompositeDeviceRepository` one lookup instead
/// of a repeated switch per operation.
protocol DeviceController {
    func fire(_ stimulus: StimulusConfig, on peripheral: CBPeripheral) async throws
    func saveStimulusConfig(_ stimulus: StimulusConfig, on peripheral: CBPeripheral) async throws
    func syncAlarm(_ alarm: Alarm, on peripheral: CBPeripheral) async throws
    func deleteAlarm(_ id: Alarm.ID, on peripheral: CBPeripheral) async throws
}
