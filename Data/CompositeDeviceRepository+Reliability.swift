import CoreBluetooth
import Foundation

// MARK: - Reliability: reconnect, power state, background restoration

/// Connection reliability: reconnect on launch and on Bluetooth power-on,
/// react to unexpected drops, and adopt peripherals handed back after a
/// background relaunch.
///
/// Methods are `internal` rather than `private` because this extension lives
/// in its own file and `private` in Swift is file-scoped.
extension CompositeDeviceRepository {
    func attemptAutoReconnect() async {
        // `startIfNeeded()` starts one of these, and the `.poweredOn` state
        // event that follows a moment later starts another. Both then raced
        // into `central.connect` for the same peripheral, stranding a
        // continuation each time ("leaked its continuation without resuming
        // it" in the log) and leaving orphaned timeouts to fire minutes
        // later against an already-connected device.
        guard !isAutoReconnecting else { return }
        isAutoReconnecting = true
        defer { isAutoReconnecting = false }

        guard let record = store.load() else { return }
        // Wait rather than bail: on a cold launch this runs before
        // CoreBluetooth has settled, and giving up here is what left the app
        // sitting on onboarding with a perfectly good paired device nearby.
        do {
            try await central.waitUntilPoweredOn()
        } catch {
            BLELog.error("Auto-reconnect aborted: \(error.localizedDescription)")
            return
        }
        guard connectedPeripheral == nil else { return }
        guard let peripheral = central.retrieveKnownPeripheral(record.peripheralIdentifier) else {
            BLELog.error("Paired device \(record.peripheralIdentifier) not known to CoreBluetooth")
            connectionStateHub.yield(.failed("Paired device not found"))
            return
        }
        scheduleReconnect(to: peripheral, family: record.family, name: record.name)
    }

    func scheduleReconnect(to peripheral: CBPeripheral, family: DeviceFamily, name: String) {
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            guard let self else { return }
            connectionStateHub.yield(.connecting)
            do {
                try await central.connect(peripheral)
                guard !Task.isCancelled else { return }
                adopt(peripheral, family: family, name: name)
            } catch {
                guard !Task.isCancelled else { return }
                BLELog.error("Reconnect failed: \(error.localizedDescription)")
                connectionStateHub.yield(.failed(error.localizedDescription))
            }
        }
    }

    func handlePowerStateChange(_ state: CBManagerState) {
        switch state {
        case .poweredOn:
            if connectedPeripheral == nil {
                Task { await attemptAutoReconnect() }
            }
        case .poweredOff:
            reconnectTask?.cancel()
            connectedPeripheral = nil
            connectionStateHub.yield(.failed("Bluetooth is off"))
            connectedDeviceHub.yield(nil)
        case .unauthorized:
            connectionStateHub.yield(.failed("Bluetooth permission denied"))
        case .unsupported:
            connectionStateHub.yield(.failed("Bluetooth not supported on this device"))
        case .resetting, .unknown:
            break
        @unknown default:
            break
        }
    }

    /// An unexpected drop (out of range, device powered off, crashed).
    /// Manual `disconnect()`/`forgetPairedDevice()` already nil out
    /// `connectedPeripheral` before CoreBluetooth's callback arrives, so by
    /// the time this runs for one of those the identifier check below no
    /// longer matches and nothing happens — no separate "was this manual"
    /// flag needed.
    func handleUnexpectedDisconnection(_ event: (peripheralID: UUID, error: Error?)) {
        guard let peripheral = connectedPeripheral, let family = connectedFamily,
              peripheral.identifier == event.peripheralID else { return }
        connectedPeripheral = nil
        connectionStateHub.yield(.disconnected)
        connectedDeviceHub.yield(nil)

        let name = store.load()?.name ?? family.displayName
        scheduleReconnect(to: peripheral, family: family, name: name)
    }

    func adoptRestoredPeripherals(_ peripherals: [CBPeripheral]) {
        guard let peripheral = peripherals.first,
              let record = store.load(),
              record.peripheralIdentifier == peripheral.identifier else { return }
        adopt(peripheral, family: record.family, name: record.name)
    }
}
