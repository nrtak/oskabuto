import Network
import SwiftUI

struct NetworkCheckView: View {
    @State private var path: NWPath?

    var body: some View {
        List {
            Section("Current connection") {
                LabeledContent("Network path") { StatusLabel(status: connectionStatus) }
                if let path, path.status == .satisfied {
                    LabeledContent("Connection type", value: interfaceNames(path))
                }
            }
            Section("Wi-Fi security · guided") {
                StatusLabel(status: .unverified("Wi-Fi security not verified"))
                SettingsSteps(steps: ["Open Wi-Fi in Settings.", "Tap the info button beside your network.", "Look for Weak Security or Privacy Warning."])
            }
        }
        .navigationTitle("Network Check").navigationBarTitleDisplayMode(.inline)
        .task {
            let monitor = NWPathMonitor()
            let updates = AsyncStream<NWPath>(bufferingPolicy: .bufferingNewest(1)) { continuation in
                monitor.pathUpdateHandler = { continuation.yield($0) }
                continuation.onTermination = { _ in monitor.cancel() }
                monitor.start(queue: DispatchQueue(label: "Kabuto.NetworkCheck"))
            }
            for await update in updates { path = update }
        }
    }

    private var connectionStatus: CheckStatus {
        guard let path else { return .pending("Checking…") }
        switch path.status {
        case .satisfied: return .verified("Available · verified")
        case .unsatisfied: return .attention("Unavailable")
        case .requiresConnection: return .attention("Connection needed")
        @unknown default: return .unverified("Not verified")
        }
    }

    private func interfaceNames(_ path: NWPath) -> String {
        let types: [(NWInterface.InterfaceType, String)] = [(.wifi, "Wi-Fi"), (.cellular, "Cellular"), (.wiredEthernet, "Ethernet")]
        let names = types.filter { path.usesInterfaceType($0.0) }.map { $0.1 }
        return names.isEmpty ? "Other" : names.joined(separator: ", ")
    }
}
