import CoreBluetooth

extension CBUUID {
    /// Full 128-bit representation, expanding 16- and 32-bit Bluetooth-SIG
    /// short forms against the Bluetooth base UUID.
    ///
    /// `CBUUID` compares equal across forms — `CBUUID(string: "1002") ==
    /// CBUUID(string: "00001002-0000-1000-8000-00805F9B34FB")` is true — but
    /// `uuidString` is *not* normalised: it returns whichever form the value
    /// was built from. A peripheral reports Bluetooth-base UUIDs in short
    /// form, so any comparison that goes through strings (a persisted
    /// override, a `GATTCharacteristicDump`, a dictionary keyed by UUID
    /// text) sees "1002" on one side and the long form on the other and
    /// finds nothing. That failure looks exactly like "this device doesn't
    /// have that characteristic".
    var canonicalString: String {
        let hex = data.map { String(format: "%02X", $0) }.joined()
        switch data.count {
        case 2: return "0000\(hex)-0000-1000-8000-00805F9B34FB"
        case 4: return "\(hex)-0000-1000-8000-00805F9B34FB"
        default:
            guard hex.count == 32 else { return uuidString.uppercased() }
            let parts = [hex.prefix(8), hex.dropFirst(8).prefix(4), hex.dropFirst(12).prefix(4),
                         hex.dropFirst(16).prefix(4), hex.dropFirst(20)]
            return parts.joined(separator: "-")
        }
    }

    /// Form-independent equality. `==` already behaves this way; this
    /// exists so lookups read the same whether they compare values or the
    /// strings derived from them.
    func matches(_ other: CBUUID) -> Bool {
        canonicalString == other.canonicalString
    }
}
