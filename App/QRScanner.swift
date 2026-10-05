import SwiftUI
import VisionKit

struct QRScanner: View {
    let onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Group {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    CameraScanner(onScan: onScan)
                } else {
                    ContentUnavailableView("Camera unavailable", systemImage: "camera", description: Text("Allow camera access in Settings, use a supported device, or paste QR contents in the checker. The simulator cannot scan."))
                }
            }.navigationTitle("Scan without opening")
                .toolbar { Button("Cancel") { dismiss() } }
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
