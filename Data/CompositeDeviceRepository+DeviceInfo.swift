import CoreBluetooth
import Foundation

// MARK: - Device information: model, firmware, battery

/// Reading the standard Device Information and Battery services, and keeping
/// the published `PavlokDevice` up to date with what they say.
///
/// Methods are `internal` rather than `private` because this extension lives
/// in its own file and `private` in Swift is file-scoped.
extension CompositeDeviceRepository {
    func readDeviceInfo() async throws -> DeviceInfo {
        let (peripheral, _) = try requireConnection()
        return try await deviceInfoReader.read(from: peripheral)
    }

    /// How many times to ask a freshly connected device for its info before
    /// settling for what we have.
    static let deviceInfoAttempts = 3
    static let deviceInfoRetryDelay: Duration = .seconds(2)

    /// Fills in model/firmware/battery and re-publishes the device. Without
    /// this its `info` stays at its empty default for the whole session, so
    /// the battery readout on the dashboard never appears no matter what the
    /// hardware reports.
    ///
    /// Retried while the battery is still missing, because this is the only
    /// moment anything asks. The standard battery service is the last read
    /// of the six and the one most likely to come back empty on a link that
    /// is still settling after a connect — and a single miss used to mean no
    /// battery for the rest of the session. Whatever *did* arrive is
    /// published on each pass, so model and firmware show up immediately and
    /// the battery fills in behind them.
    func publishDeviceInfo(for peripheral: CBPeripheral, of device: PavlokDevice) async {
        var enriched = device
        for attempt in 1...Self.deviceInfoAttempts {
            guard connectedPeripheral?.identifier == peripheral.identifier else { return }
            if let info = try? await deviceInfoReader.read(from: peripheral) {
                guard connectedPeripheral?.identifier == peripheral.identifier else { return }
                enriched.info = info
                let battery = info.batteryLevelPercent.map(String.init) ?? "?"
                BLELog.info("Device info: model=\(info.modelNumber ?? "?") fw=\(info.firmwareRevision ?? "?") battery=\(battery)")
                connectedDeviceHub.yield(enriched)
                if info.batteryLevelPercent != nil { return }
            }
            guard attempt < Self.deviceInfoAttempts else { return }
            BLELog.info("No battery level yet — re-reading device info (attempt \(attempt + 1) of \(Self.deviceInfoAttempts))")
            try? await Task.sleep(for: Self.deviceInfoRetryDelay)
        }
    }
}
