import CoreBluetooth
import Foundation
import UIKit

// MARK: - Device information: model, firmware, battery

/// Reading the standard Device Information and Battery services, and keeping
/// the published `PavlokDevice` up to date with what they say.
///
/// Everything that learns something about the device goes through
/// `publish(_:for:)` — a read that only ever reached its caller is how the
/// dashboard card and the detail screen came to show two different battery
/// percentages at the same time.
///
/// Methods are `internal` rather than `private` because this extension lives
/// in its own file and `private` in Swift is file-scoped.
extension CompositeDeviceRepository {
    /// Reads model/firmware/battery from the device *and* republishes the
    /// connected device with them, so a refresh on the detail or diagnostics
    /// screen also moves the dashboard card behind it.
    func readDeviceInfo() async throws -> DeviceInfo {
        let (peripheral, _) = try requireConnection()
        let info = try await deviceInfoReader.read(from: peripheral)
        publish(info, for: peripheral)
        return info
    }

    /// `UIApplication.willEnterForegroundNotification`, named here so the
    /// repository's own body doesn't have to reach for UIKit. The one place
    /// this layer cares about the app lifecycle: a wearable keeps draining
    /// while the phone is in a pocket.
    static let willEnterForeground = UIApplication.willEnterForegroundNotification

    /// Re-reads device info when there is something to read it from. The
    /// foreground hook: a percentage that moved while the app was
    /// backgrounded is corrected on the first frame instead of waiting for
    /// the wearable's next notification.
    func refreshDeviceInfoIfConnected() async {
        guard connectedPeripheral != nil else { return }
        _ = try? await readDeviceInfo()
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
    /// moment anything *asks* — after it, `startBatteryMonitoring` takes
    /// over and the device tells us. The standard battery service is the
    /// last read of the six and the one most likely to come back empty on a
    /// link that is still settling after a connect — and a single miss used
    /// to mean no battery for the rest of the session. Whatever *did* arrive
    /// is published on each pass, so model and firmware show up immediately
    /// and the battery fills in behind them.
    func publishDeviceInfo(for peripheral: CBPeripheral) async {
        for attempt in 1...Self.deviceInfoAttempts {
            guard connectedPeripheral?.identifier == peripheral.identifier else { return }
            if let info = try? await deviceInfoReader.read(from: peripheral) {
                publish(info, for: peripheral)
                let battery = info.batteryLevelPercent.map(String.init) ?? "?"
                BLELog.info("Device info: model=\(info.modelNumber ?? "?") fw=\(info.firmwareRevision ?? "?") battery=\(battery)")
                if info.batteryLevelPercent != nil { return }
            }
            guard attempt < Self.deviceInfoAttempts else { return }
            BLELog.info("No battery level yet — re-reading device info (attempt \(attempt + 1) of \(Self.deviceInfoAttempts))")
            try? await Task.sleep(for: Self.deviceInfoRetryDelay)
        }
    }

    /// Hands `info` to everyone watching `connectedDevice`, by amending the
    /// device that is already published rather than a copy taken earlier —
    /// an `await` ago the battery monitor may have moved it.
    ///
    /// Ignored when the peripheral is no longer the connected one: a read
    /// that was in flight across a disconnect must not resurrect the device
    /// that went away.
    func publish(_ info: DeviceInfo, for peripheral: CBPeripheral) {
        guard connectedPeripheral?.identifier == peripheral.identifier,
              var device = connectedDeviceHub.latest ?? nil,
              device.peripheralIdentifier == peripheral.identifier,
              device.info != info else { return }
        device.info = info
        connectedDeviceHub.yield(device)
    }
}
