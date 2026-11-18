import SwiftUI
import VisionKit
import AVFoundation
import PhotosUI
import Vision
import ImageIO

struct QRPhotoPicker: View {
    let onStart: () -> Void
    let onScan: (String) -> Void
    @State private var selected: PhotosPickerItem?
    @State private var candidates: [String] = []
    @State private var message = ""

    var body: some View {
        PhotosPicker(selection: $selected, matching: .images) {
            Label("Choose a screenshot or photo", systemImage: "photo")
        }
        .task(id: selected) {
            guard let selected else { return }
            onStart()
            message = "Reading QR codes…"
            candidates = []
            do {
                guard let data = try await selected.loadTransferable(type: Data.self) else { throw CocoaError(.fileReadCorruptFile) }
                let values = try await Self.decode(data)
                try Task.checkCancellation()
                if values.count == 1 {
                    message = ""
                    onScan(values[0])
                } else {
                    message = values.isEmpty ? "No readable QR code found. Try a clearer image or enter its contents." : "Choose a QR code to inspect."
                    candidates = values
                }
            } catch {
                guard !Task.isCancelled else { return }
                message = "Couldn’t read that image. Try another photo or enter the QR contents."
            }
            self.selected = nil
        }
        if !message.isEmpty { Text(message).font(.footnote) }
        ForEach(candidates, id: \.self) { value in
            Button {
                message = ""; candidates = []; onScan(value)
            } label: { Text(verbatim: value).lineLimit(3) }
        }
    }

    private nonisolated static func decode(_ data: Data) async throws -> [String] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 3072
              ] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        var seen: Set<String> = []
        return (request.results ?? []).compactMap(\.payloadStringValue).filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

struct QRScanner: View {
    let onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @Environment(\.openURL) private var openURL
    @State private var permission = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var scannerFailed = false

    var body: some View {
        NavigationStack {
            Group {
                if !DataScannerViewController.isSupported {
                    fallback("Use QR contents", "Camera scanning is unavailable on this device. You can paste or type the code’s contents.")
                } else if permission == .notDetermined {
                    ProgressView("Waiting for camera access…")
                } else if permission == .denied {
                    fallback("Camera access is off", "Allow camera access in Settings or enter the QR contents yourself.")
                } else if permission == .authorized && DataScannerViewController.isAvailable && !scannerFailed {
                    CameraScanner(onScan: onScan, onUnavailable: { scannerFailed = true })
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
    let onUnavailable: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan, onUnavailable: onUnavailable) }
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced, recognizesMultipleItems: false, isHighlightingEnabled: true)
        controller.delegate = context.coordinator
        do { try controller.startScanning() } catch { context.coordinator.unavailable() }
        return controller
    }
    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}
    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) { controller.stopScanning() }
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        let onUnavailable: () -> Void
        var delivered = false
        init(onScan: @escaping (String) -> Void, onUnavailable: @escaping () -> Void) {
            self.onScan = onScan
            self.onUnavailable = onUnavailable
        }
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !delivered else { return }
            for item in addedItems {
                if case let .barcode(code) = item, let value = code.payloadStringValue {
                    delivered = true; dataScanner.stopScanning(); onScan(value); return
                }
            }
        }
        func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) { unavailable() }
        func unavailable() {
            guard !delivered else { return }
            delivered = true
            DispatchQueue.main.async { self.onUnavailable() }
        }
    }
}
