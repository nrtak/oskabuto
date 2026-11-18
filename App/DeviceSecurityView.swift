import Darwin
import LocalAuthentication
import SwiftUI

struct DeviceSecurityView: View {
    @Environment(\.scenePhase) private var phase
    @State private var passcode = "Checking…"
    @State private var biometricName = "Biometrics"
    @State private var biometrics = "Checking…"
    @State private var releaseResult = ""
    @State private var checkingRelease = false

    var body: some View {
        List {
            Section("Screen lock") {
                LabeledContent("Device passcode", value: passcode)
                LabeledContent(biometricName, value: biometrics)
                Text("These checks run on your device without asking you to unlock it.").font(.footnote)
            }
            Section("Software update") {
                LabeledContent("Installed · verified", value: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")
                Button(checkingRelease ? "Checking Apple’s releases…" : "Check for a newer release") {
                    checkingRelease = true
                    Task {
                        releaseResult = await AppleReleaseCheck.result()
                        checkingRelease = false
                    }
                }.disabled(checkingRelease)
                if !releaseResult.isEmpty { Text(releaseResult) }
                Text("This downloads Apple’s public release list. Kabuto compares your model and version locally.").font(.footnote)
            }
            Section("Check in Settings · guided") {
                Text("Open Settings → General → Software Update to see the update or security fixes Apple offers this device.")
                NavigationLink("Browser and device privacy") { PrivacyChecksView() }
            }
        }
        .navigationTitle("Device Security").navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refreshLock)
        .onChange(of: phase) { _, newPhase in if newPhase == .active { refreshLock() } }
    }

    private func refreshLock() {
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            passcode = "Set · verified"
        } else {
            passcode = (error as? LAError)?.code == .passcodeNotSet ? "Not set · verified" : "Unknown"
        }
        var biometricError: NSError?
        let available = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &biometricError)
        switch context.biometryType {
        case .faceID: biometricName = "Face ID"
        case .touchID: biometricName = "Touch ID"
        default: biometricName = "Biometrics"
        }
        if available {
            biometrics = "Set up · verified"
        } else {
            switch (biometricError as? LAError)?.code {
            case .biometryNotEnrolled: biometrics = "Not set up · verified"
            case .biometryLockout: biometrics = "Temporarily locked · verified"
            default: biometrics = "Unavailable to Kabuto"
            }
        }
    }
}

private enum AppleReleaseCheck {
    @MainActor static func result() async -> String {
        let fallback = "Couldn’t confirm a release for this device. Check Software Update in Settings."
        var machineInfo = utsname()
        guard uname(&machineInfo) == 0 else { return fallback }
        let model = withUnsafeBytes(of: &machineInfo.machine) {
            String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
        }
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 12
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        do {
            let (data, response) = try await session.data(from: URL(string: "https://gdmf.apple.com/v2/pmv")!)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return fallback }
            let catalog = try JSONDecoder().decode(AppleReleaseCatalog.self, from: data)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
            let today = formatter.string(from: Date())
            guard let latest = catalog.latestVersion(for: model, on: today) else { return fallback }
            let installed = UIDevice.current.systemVersion
            switch installed.compare(latest, options: .numeric) {
            case .orderedSame: return "Your version matches Apple’s latest listed public release for this model (\(latest))."
            case .orderedAscending: return "Apple lists a newer version for this model (\(latest)). Check Software Update to install it."
            default: return "Your version is newer than Apple’s listed public release (\(latest)). Check availability in Settings."
            }
        } catch { return fallback }
    }
}
