import Foundation

/// Extra effort required to silence an alarm, mirroring the Android app's
/// "wake-up guarantees". `.none` just stops the alarm on tap.
enum DismissChallenge: String, CaseIterable, Codable, Identifiable {
    case none
    case mathPuzzle
    case jumpingJacks
    case qrCodeScan

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "None"
        case .mathPuzzle: return "Math puzzle"
        case .jumpingJacks: return "Jumping jacks"
        case .qrCodeScan: return "Scan a QR code"
        }
    }
}
