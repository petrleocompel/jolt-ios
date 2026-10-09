import Foundation

/// RFC 4648 §5 base64url without padding — the only base64 flavour the relay
/// protocol uses for its own fields (`kid`, nonce, ciphertext, `payloadKey`,
/// tokens). App Attest blobs are the exception and go as standard base64.
enum Base64URL {
    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Nil for anything that isn't base64url, including padded or standard
    /// base64 input: the contract says unpadded base64url, and accepting the
    /// other spellings would only hide a sender bug.
    static func decode(_ string: String) -> Data? {
        guard !string.contains(where: { "+/=".contains($0) }) else { return nil }
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        guard remainder != 1 else { return nil }
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: base64)
    }
}
