import CoreBluetooth
import Foundation

/// Finding devices.
///
/// The subtlety worth keeping together in one place: a scan alone cannot see
/// a device the phone is already connected to, because a connected peripheral
/// stops advertising. Seeding from `retrieveConnectedPeripherals` and the
/// stored pairing is what makes an already-paired Pavlok discoverable.
extension BluetoothCentralManager {
    /// Looks up an already-known (previously connected or bonded)
    /// peripheral by identifier without scanning — the right way to
    /// reconnect to a device you've paired before.
    func retrieveKnownPeripheral(_ identifier: UUID) -> CBPeripheral? {
        central.retrievePeripherals(withIdentifiers: [identifier]).first
    }

    /// Peripherals iOS is *already* connected to. These never appear in a
    /// scan — CoreBluetooth only reports advertisements, and a connected
    /// device has stopped advertising — so they have to be pulled in
    /// separately or a device paired at the system level looks missing.
    func retrieveSystemConnectedPeripherals() -> [CBPeripheral] {
        central.retrieveConnectedPeripherals(withServices: Self.knownServiceUUIDs)
    }

    /// Starts a scan and yields everything found. `seedIdentifiers` are
    /// previously-paired peripherals to surface immediately without waiting
    /// for an advertisement.
    func startScan(serviceUUIDs: [CBUUID]?, seedIdentifiers: [UUID] = []) -> AsyncStream<DiscoveredPeripheral> {
        AsyncStream { continuation in
            self.scanContinuation = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.stopScan() }
            }

            Task { @MainActor in
                do {
                    try await self.waitUntilPoweredOn()
                } catch {
                    BLELog.error("Scan aborted: \(error.localizedDescription)")
                    continuation.finish()
                    return
                }

                // Seed before advertisements so an already-connected or
                // previously-bonded device shows up on the first frame.
                for peripheral in self.central.retrievePeripherals(withIdentifiers: seedIdentifiers) {
                    BLELog.info("Seeded known peripheral \(peripheral.identifier) name=\(peripheral.name ?? "nil")")
                    continuation.yield(DiscoveredPeripheral(
                        peripheral: peripheral, advertisedName: nil, rssi: nil, wasAlreadyConnected: false
                    ))
                }
                for peripheral in self.retrieveSystemConnectedPeripherals() {
                    BLELog.info("Seeded system-connected peripheral \(peripheral.identifier) name=\(peripheral.name ?? "nil")")
                    continuation.yield(DiscoveredPeripheral(
                        peripheral: peripheral, advertisedName: nil, rssi: nil, wasAlreadyConnected: true
                    ))
                }

                BLELog.info("Scanning for services=\(serviceUUIDs?.map(\.uuidString).joined(separator: ",") ?? "any")")
                // `allowDuplicates: false` — we de-duplicate by identifier
                // upstream anyway, and duplicates burn battery.
                self.central.scanForPeripherals(
                    withServices: serviceUUIDs,
                    options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
                )
            }
        }
    }

    func stopScan() {
        if central.isScanning {
            central.stopScan()
            BLELog.info("Scan stopped")
        }
        scanContinuation?.finish()
        scanContinuation = nil
    }
}
