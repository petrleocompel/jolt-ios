import CoreBluetooth
import Foundation

/// Service and characteristic discovery, plus the two diagnostic sweeps the
/// app exposes: a full GATT dump and a notification capture.
///
/// Split out of `BluetoothCentralManager.swift` to keep that file readable —
/// these are the operations that exist to *learn* about a device rather than
/// to drive one, and they are what Diagnostics is built on.
extension BluetoothCentralManager {
    func resolveCharacteristic(
        _ characteristicUUID: CBUUID,
        in serviceUUID: CBUUID,
        on peripheral: CBPeripheral
    ) async throws -> CBCharacteristic {
        if let service = peripheral.services?.first(where: { $0.uuid.matches(serviceUUID) }),
           let characteristic = service.characteristics?.first(where: { $0.uuid.matches(characteristicUUID) }) {
            return characteristic
        }

        try await discoverServices([serviceUUID], on: peripheral)
        guard let service = peripheral.services?.first(where: { $0.uuid.matches(serviceUUID) }) else {
            let present = peripheral.services?.map(\.uuid.uuidString).joined(separator: ",") ?? "none"
            BLELog.error("Service \(serviceUUID.uuidString) not found. Present: \(present)")
            throw BluetoothError.serviceNotFound(serviceUUID)
        }
        // Discover *all* characteristics rather than only the one asked for:
        // the extra ones cost nothing and make the "what's actually on this
        // device" log line useful when a UUID guess turns out wrong.
        try await discoverCharacteristics(nil, in: service, on: peripheral)
        guard let characteristic = service.characteristics?.first(where: { $0.uuid.matches(characteristicUUID) }) else {
            let present = service.characteristics?.map(\.uuid.uuidString).joined(separator: ",") ?? "none"
            BLELog.error("Characteristic \(characteristicUUID.uuidString) not found in \(serviceUUID.uuidString). Present: \(present)")
            throw BluetoothError.characteristicNotFound(characteristicUUID)
        }
        return characteristic
    }

    func discoverServices(_ uuids: [CBUUID]?, on peripheral: CBPeripheral, timeout: Duration = .seconds(10)) async throws {
        try await withTimeout(timeout, description: "discover services") {
            try await withCheckedThrowingContinuation { continuation in
                self.discoverServicesContinuations[peripheral.identifier] = continuation
                peripheral.discoverServices(uuids)
            }
        } onTimeout: { [weak self] in
            self?.discoverServicesContinuations.removeValue(forKey: peripheral.identifier)?
                .resume(throwing: BluetoothError.timedOut("discover services"))
        }
    }

    func discoverCharacteristics(
        _ uuids: [CBUUID]?,
        in service: CBService,
        on peripheral: CBPeripheral,
        timeout: Duration = .seconds(10)
    ) async throws {
        try await withTimeout(timeout, description: "discover characteristics") {
            try await withCheckedThrowingContinuation { continuation in
                self.discoverCharacteristicsContinuations[peripheral.identifier, default: [:]][service.uuid.canonicalString] = continuation
                peripheral.discoverCharacteristics(uuids, for: service)
            }
        } onTimeout: { [weak self] in
            self?.discoverCharacteristicsContinuations[peripheral.identifier]?.removeValue(forKey: service.uuid.canonicalString)?
                .resume(throwing: BluetoothError.timedOut("discover characteristics"))
        }
    }

    /// Discovers every service and characteristic on the peripheral. Used by
    /// the diagnostics screen: with the Pavlok wire protocol only partly
    /// recovered, seeing the device's real GATT table is the fastest way to
    /// tell a wrong UUID from a wrong payload.
    /// - Parameter readingValues: also reads every readable characteristic.
    ///   Reads are non-destructive — no stimulus can fire from one — so this
    ///   is the safe way to work out which config characteristic is which:
    ///   the value a characteristic already holds usually gives it away.
    func dumpGATT(on peripheral: CBPeripheral, readingValues: Bool = false) async throws -> [GATTCharacteristicDump] {
        guard peripheral.state == .connected else { throw BluetoothError.bluetoothUnavailable }
        try await discoverServices(nil, on: peripheral)
        var dump: [GATTCharacteristicDump] = []
        for service in peripheral.services ?? [] {
            try? await discoverCharacteristics(nil, in: service, on: peripheral)
            for characteristic in service.characteristics ?? [] {
                var value: String?
                if readingValues, characteristic.properties.contains(.read) {
                    // A short timeout per characteristic: one unresponsive
                    // handle shouldn't stall a 40-characteristic sweep.
                    let data = try? await read(
                        characteristic.uuid,
                        from: service.uuid,
                        on: peripheral,
                        timeout: .seconds(3)
                    )
                    value = data.map { $0.map { String(format: "%02X", $0) }.joined(separator: " ") }
                }
                dump.append(GATTCharacteristicDump(
                    serviceUUID: service.uuid.uuidString,
                    uuid: characteristic.uuid.uuidString,
                    properties: characteristic.properties.labels,
                    value: value
                ))
            }
        }
        BLELog.info("GATT dump: \(dump.count) characteristics across \(peripheral.services?.count ?? 0) services")
        for entry in dump {
            let value = entry.value.map { " = \($0)" } ?? ""
            BLELog.debug("  \(entry.serviceUUID) / \(entry.uuid) [\(entry.properties.joined(separator: ","))]\(value)")
        }
        return dump
    }

    /// Subscribes to every notifying characteristic and logs whatever
    /// arrives.
    ///
    /// This is the closest thing to an HCI capture that runs on the phone.
    /// The parts of this protocol still missing are commands the app is
    /// supposed to *send*, and the device announces a good deal of what it
    /// does — so pressing the physical button, which fires a stimulus
    /// through firmware we cannot read, makes the device describe that event
    /// in its own encoding.
    ///
    /// Returns the number of characteristics successfully subscribed.
    @discardableResult
    func captureAllNotifications(on peripheral: CBPeripheral) async throws -> Int {
        guard peripheral.state == .connected else { throw BluetoothError.bluetoothUnavailable }
        stopNotificationCapture()
        try await discoverServices(nil, on: peripheral)

        var subscribed = 0
        for service in peripheral.services ?? [] {
            try? await discoverCharacteristics(nil, in: service, on: peripheral)
            for characteristic in service.characteristics ?? [] {
                guard characteristic.properties.contains(.notify)
                    || characteristic.properties.contains(.indicate) else { continue }
                guard let stream = try? await subscribe(characteristic.uuid, in: service.uuid, on: peripheral)
                else { continue }
                subscribed += 1
                let label = "\(service.uuid.uuidString)/\(characteristic.uuid.uuidString)"
                captureTasks.append(Task { @MainActor in
                    for await data in stream {
                        let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
                        BLELog.info("EVENT \(label): \(hex.isEmpty ? "(empty)" : hex)")
                    }
                })
            }
        }
        BLELog.info("Listening on \(subscribed) notifying characteristic(s) — trigger something on the device now")
        return subscribed
    }

    func stopNotificationCapture() {
        guard !captureTasks.isEmpty else { return }
        captureTasks.forEach { $0.cancel() }
        captureTasks.removeAll()
        BLELog.info("Stopped listening for device events")
    }

    /// Like `captureAllNotifications`, but yields each notification as a
    /// structured `DeviceEvent` instead of only logging it — the feed the
    /// poke trigger (and its "learn a gesture" capture) consumes.
    ///
    /// Subscribes to every notifying characteristic because the exact one the
    /// device uses for a button tap isn't pinned down yet (see `jolt-firmware`
    /// `docs/04`); matching is done by the consumer against a learned example,
    /// so an over-broad subscription here is harmless and future-proof.
    ///
    /// The stream finishes when `stopEventStream()` is called or the caller
    /// stops iterating.
    func streamAllNotifications(on peripheral: CBPeripheral) async throws -> AsyncStream<DeviceEvent> {
        guard peripheral.state == .connected else { throw BluetoothError.bluetoothUnavailable }
        stopEventStream()
        try await discoverServices(nil, on: peripheral)

        return AsyncStream { continuation in
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.stopEventStream() }
            }
            Task { @MainActor in
                var subscribed = 0
                for service in peripheral.services ?? [] {
                    try? await self.discoverCharacteristics(nil, in: service, on: peripheral)
                    for characteristic in service.characteristics ?? [] {
                        guard characteristic.properties.contains(.notify)
                            || characteristic.properties.contains(.indicate) else { continue }
                        guard let stream = try? await self.subscribe(
                            characteristic.uuid, in: service.uuid, on: peripheral
                        ) else { continue }
                        subscribed += 1
                        let serviceUUID = service.uuid.canonicalString
                        let charUUID = characteristic.uuid.canonicalString
                        self.eventStreamTasks.append(Task { @MainActor in
                            for await data in stream {
                                continuation.yield(DeviceEvent(
                                    serviceUUID: serviceUUID,
                                    characteristicUUID: charUUID,
                                    data: data
                                ))
                            }
                        })
                    }
                }
                BLELog.info("Poke trigger listening on \(subscribed) notifying characteristic(s)")
            }
        }
    }

    func stopEventStream() {
        guard !eventStreamTasks.isEmpty else { return }
        eventStreamTasks.forEach { $0.cancel() }
        eventStreamTasks.removeAll()
    }

    /// Finds the first characteristic from `candidates` that the device
    /// actually exposes and that accepts writes. Lets a controller carry a
    /// list of plausible UUIDs and let the hardware pick, instead of failing
    /// outright when one guess is wrong.
    func firstWritableCharacteristic(
        among candidates: [CBUUID],
        in serviceUUID: CBUUID,
        on peripheral: CBPeripheral
    ) async -> CBUUID? {
        try? await discoverServices([serviceUUID], on: peripheral)
        guard let service = peripheral.services?.first(where: { $0.uuid.matches(serviceUUID) }) else { return nil }
        try? await discoverCharacteristics(nil, in: service, on: peripheral)
        for candidate in candidates {
            if let match = service.characteristics?.first(where: { $0.uuid.matches(candidate) }),
               match.properties.contains(.write) || match.properties.contains(.writeWithoutResponse) {
                return candidate
            }
        }
        return nil
    }
}
