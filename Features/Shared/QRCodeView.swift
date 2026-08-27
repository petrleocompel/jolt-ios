import CoreImage.CIFilterBuiltins
import SwiftUI

/// Renders `content` as a QR code — used for "here's my invite code, scan
/// me" in `AddFriendView`.
struct QRCodeView: View {
    let content: String

    var body: some View {
        if let image = Self.generate(content) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
        } else {
            Color.secondary.opacity(0.2)
        }
    }

    private static func generate(_ string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        guard let outputImage = filter.outputImage else { return nil }
        let transformed = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
