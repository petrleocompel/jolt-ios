import CoreBluetooth

/// Shock Clock Max GATT layout. Both service UUIDs and the fact that
/// `66651001`/`66651002` are a write/notify control-point pair are confirmed
/// from the Android binary (`SCMaxControlPointsService`). The messages sent
/// over that control point are ESF-encoded (see `ESF/`), but the opcode
/// table itself is not recovered — see `ProtocolMap.swift`.
enum SCMaxGATT {
    static let controlPointsService = CBUUID(string: "66651000-39F4-11ED-92BD-832ABAC11AB4")
    static let controlPointWrite = CBUUID(string: "66651001-39F4-11ED-92BD-832ABAC11AB4")
    static let controlPointNotify = CBUUID(string: "66651002-39F4-11ED-92BD-832ABAC11AB4")

    /// Second service seen in the binary (`scmaxD` / bulk transfer symbols
    /// nearby). Purpose unconfirmed — likely bulk file/log transfer given
    /// `SCMaxBulkMessageType` / `SCMaxFileType` in the same source tree.
    static let secondaryService = CBUUID(string: "66657000-39F4-11ED-92BD-832ABAC11AB4")
    static let secondaryCharacteristic = CBUUID(string: "66657001-39F4-11ED-92BD-832ABAC11AB4")
}
