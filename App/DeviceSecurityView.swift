import Darwin
import LocalAuthentication
import SwiftUI

struct DeviceSecurityView: View {
    @Environment(\.scenePhase) private var phase
    @State private var passcode = CheckStatus.pending("Checking…")
    @State private var biometricName = "Biometrics"
    @State private var biometrics = CheckStatus.pending("Checking…")
    @State private var releaseResult: CheckStatus?
    @State private var checkingRelease = false

    var body: some View {
        List {
            Section("Screen lock") {
                LabeledContent("Device passcode") { StatusLabel(status: passcode) }
                LabeledContent(biometricName) { StatusLabel(status: biometrics) }
            }
            Section("Software update") {
                LabeledContent("Installed version") { StatusLabel(status: .verified("\(UIDevice.current.systemName) \(UIDevice.current.systemVersion) · verified")) }
                Button(checkingRelease ? "Checking Apple’s releases…" : "Check for a newer release") {
                    checkingRelease = true
                    Task {
                        releaseResult = await AppleReleaseCheck.result()
                        checkingRelease = false
                    }
                }.disabled(checkingRelease)
                if checkingRelease { ProgressView("Checking") }
                else if let releaseResult { StatusLabel(status: releaseResult) }
                Text("This downloads Apple’s public release list. Kabuto compares your model and version locally.").font(.footnote)
            }
            Section("Check in Settings · guided") {
                SettingsSteps(steps: ["Open Settings.", "Tap General.", "Open Software Update to see available updates."])
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
            passcode = .verified("Set · verified")
        } else {
            passcode = (error as? LAError)?.code == .passcodeNotSet ? .attention("No passcode set") : .unverified("Not verified")
        }
        var biometricError: NSError?
        let available = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &biometricError)
        switch context.biometryType {
        case .faceID: biometricName = "Face ID"
        case .touchID: biometricName = "Touch ID"
        default: biometricName = "Biometrics"
        }
        if available {
            biometrics = .verified("Set up · verified")
        } else {
            switch (biometricError as? LAError)?.code {
            case .biometryNotEnrolled: biometrics = .attention("Not set up")
            case .biometryLockout: biometrics = .attention("Temporarily locked")
            default: biometrics = .unverified("Not verified")
            }
        }
    }
}

private enum AppleReleaseCheck {
    @MainActor static func result() async -> CheckStatus {
        let fallback = CheckStatus.unverified("Latest version not verified. Check Settings.")
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
            case .orderedSame: return .verified("Matches Apple’s listed release · \(latest)")
            case .orderedAscending: return .attention("Newer release listed · \(latest)")
            default: return .unverified("Update status not verified. Apple lists \(latest).")
            }
        } catch { return fallback }
    }
}
