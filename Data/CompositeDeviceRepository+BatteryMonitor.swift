import CoreBluetooth
import Foundation

// MARK: - Battery: keeping the published level current for a whole session

/// The connect-time read in `publishDeviceInfo` happens exactly once. On its
/// own that froze the dashboard's battery readout at whatever the wearable
/// said the moment it connected — a day's drain was invisible until something
/// forced a reconnect.
///
/// This keeps it moving for as long as the link lasts: the standard battery
/// service (0x180F / 0x2A19) is notifiable on every Pavlok seen so far, so
/// the device pushes each change and the radio stays idle in between. A
/// device that declares the characteristic read-only gets polled instead,
/// slowly — battery percentage moves in single digits per hour, and a tight
/// poll would cost more charge than it reports on.
///
/// Methods are `internal` rather than `private` because this extension lives
/// in its own file and `private` in Swift is file-scoped.
extension CompositeDeviceRepository {
    /// How often a device that can't notify is re-read. Deliberately long:
    /// see the note above about what the poll itself costs.
    static let batteryPollInterval: Duration = .seconds(15 * 60)

    /// One subscription per connection. Cancels any previous one first, so a
    /// reconnect (which goes through `adopt` again) replaces its monitor
    /// rather than stacking a second one on top.
    func startBatteryMonitoring(for peripheral: CBPeripheral) {
        stopBatteryMonitoring()
        batteryMonitorTask = Task { [weak self] in
            await self?.monitorBattery(for: peripheral)
        }
    }

    /// Teardown. Cancelling the task terminates the `AsyncStream`, which
    /// unregisters the notify continuation — the same way the diagnostics
    /// capture and the poke trigger let go of their subscriptions.
    func stopBatteryMonitoring() {
        batteryMonitorTask?.cancel()
        batteryMonitorTask = nil
    }

    private func monitorBattery(for peripheral: CBPeripheral) async {
        do {
            let levels = try await central.subscribe(
                StandardGATT.batteryLevel,
                in: StandardGATT.batteryService,
                on: peripheral
            )
            for await data in levels {
                guard !Task.isCancelled else { return }
                publishBatteryLevel(from: data, for: peripheral)
            }
        } catch {
            // `subscribe` throws `characteristicNotFound` when 0x2A19 exists
            // but declares neither notify nor indicate, which is the case
            // worth falling back for. Anything else (a link that dropped
            // mid-subscribe) is handled the same way: a slow poll is a
            // correct, if duller, answer to all of them.
            guard !Task.isCancelled else { return }
            BLELog.info("Battery level won't notify (\(error.localizedDescription)) — polling instead")
            await pollBatteryLevel(for: peripheral)
        }
    }

    private func pollBatteryLevel(for peripheral: CBPeripheral) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.batteryPollInterval)
            guard !Task.isCancelled,
                  connectedPeripheral?.identifier == peripheral.identifier else { return }
            guard let data = try? await central.read(
                StandardGATT.batteryLevel,
                from: StandardGATT.batteryService,
                on: peripheral
            ) else { continue }
            publishBatteryLevel(from: data, for: peripheral)
        }
    }

    /// 0x2A19 is a single byte of percent.
    private func publishBatteryLevel(from data: Data, for peripheral: CBPeripheral) {
        guard let level = data.first,
              let device = connectedDeviceHub.latest ?? nil,
              device.info.batteryLevelPercent != Int(level) else { return }
        var info = device.info
        info.batteryLevelPercent = Int(level)
        BLELog.info("Battery level now \(level)%")
        publish(info, for: peripheral)
    }
}
