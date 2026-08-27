import AVFoundation
import SwiftUI

/// Scan any QR code to dismiss. The Android app anchors this to a specific
/// code the user prints and places somewhere inconvenient (e.g. the
/// bathroom); v1 accepts any code — printing a specific target code is a
/// follow-up, not a protocol-recovery blocker.
struct QRCodeChallengeView: View {
    let onSolved: () -> Void

    var body: some View {
        ZStack {
            QRScannerRepresentable(onCodeScanned: onSolved)
                .ignoresSafeArea()

            VStack {
                Text("Scan a QR code to dismiss")
                    .font(.headline)
                    .padding()
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 48)
                Spacer()
            }
        }
        .accessibilityIdentifier("qrCodeChallengeScreen")
    }
}

private struct QRScannerRepresentable: UIViewControllerRepresentable {
    let onCodeScanned: () -> Void

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let controller = QRScannerViewController()
        controller.onCodeScanned = onCodeScanned
        return controller
    }

    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}
}

final class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCodeScanned: (() -> Void)?
    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        configureSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [session] in session.startRunning() }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if session.isRunning { session.stopRunning() }
    }

    private func configureSession() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)
        previewLayer = preview
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard metadataObjects.contains(where: { $0.type == .qr }) else { return }
        session.stopRunning()
        onCodeScanned?()
    }
}
