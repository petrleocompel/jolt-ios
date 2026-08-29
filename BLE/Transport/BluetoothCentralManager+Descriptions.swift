import CoreBluetooth
import Foundation

// MARK: - Log-friendly descriptions

extension CBManagerState {
    var label: String {
        switch self {
        case .unknown: return "unknown"
        case .resetting: return "resetting"
        case .unsupported: return "unsupported"
        case .unauthorized: return "unauthorized"
        case .poweredOff: return "poweredOff"
        case .poweredOn: return "poweredOn"
        @unknown default: return "unrecognised(\(rawValue))"
        }
    }
}

extension CBPeripheralState {
    var label: String {
        switch self {
        case .disconnected: return "disconnected"
        case .connecting: return "connecting"
        case .connected: return "connected"
        case .disconnecting: return "disconnecting"
        @unknown default: return "unrecognised(\(rawValue))"
        }
    }
}

extension CBCharacteristicProperties {
    var labels: [String] {
        var labels: [String] = []
        if contains(.broadcast) { labels.append("broadcast") }
        if contains(.read) { labels.append("read") }
        if contains(.writeWithoutResponse) { labels.append("writeNoResp") }
        if contains(.write) { labels.append("write") }
        if contains(.notify) { labels.append("notify") }
        if contains(.indicate) { labels.append("indicate") }
        if contains(.authenticatedSignedWrites) { labels.append("signedWrite") }
        if contains(.extendedProperties) { labels.append("extended") }
        return labels
    }
}
