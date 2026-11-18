import SwiftUI
import VisionKit
import AVFoundation

struct QRScanner: View {
    let onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @Environment(\.openURL) private var openURL
    @State private var permission = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        NavigationStack {
            Group {
                if !DataScannerViewController.isSupported {
                    fallback("Use QR contents", "Camera scanning is unavailable on this device. You can paste or type the code’s contents.")
                } else if permission == .notDetermined {
                    ProgressView("Waiting for camera access…")
                } else if permission == .denied {
                    fallback("Camera access is off", "Allow camera access in Settings or enter the QR contents yourself.")
                } else if permission == .authorized && DataScannerViewController.isAvailable {
                    CameraScanner(onScan: onScan)
                } else {
                    fallback("Camera unavailable", "You can still check a code by pasting or typing its contents.")
                }
            }
            .navigationTitle("Scan QR code").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Cancel") { dismiss() } }
            .task {
                guard DataScannerViewController.isSupported else { return }
                if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
                    _ = await AVCaptureDevice.requestAccess(for: .video)
                }
                permission = AVCaptureDevice.authorizationStatus(for: .video)
            }
            .onChange(of: phase) { _, value in
                if value == .active { permission = AVCaptureDevice.authorizationStatus(for: .video) }
            }
        }
    }

    private func fallback(_ title: String, _ details: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: "qrcode.viewfinder")
        } description: {
            Text(details)
        } actions: {
            if permission == .denied && DataScannerViewController.isSupported {
                Button("Open camera settings") { openURL(URL(string: UIApplication.openSettingsURLString)!) }
            }
            Button("Enter QR contents") { dismiss() }.buttonStyle(.borderedProminent)
        }
    }
}

private struct CameraScanner: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced, recognizesMultipleItems: false, isHighlightingEnabled: true)
        controller.delegate = context.coordinator
        do { try controller.startScanning() } catch { context.coordinator.showError(on: controller, error: error) }
        return controller
    }
    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}
    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) { controller.stopScanning() }
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        var delivered = false
        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !delivered else { return }
            for item in addedItems {
                if case let .barcode(code) = item, let value = code.payloadStringValue {
                    delivered = true; dataScanner.stopScanning(); onScan(value); return
                }
            }
        }
        func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) { showError(on: dataScanner, error: error) }
        func showError(on controller: UIViewController, error: Error) {
            DispatchQueue.main.async {
                let alert = UIAlertController(title: "Scanning unavailable", message: "Use manual entry or check camera permissions. \(error.localizedDescription)", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default)); controller.present(alert, animated: true)
            }
        }
    }
}
