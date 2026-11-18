import Network
import SwiftUI

struct NetworkCheckView: View {
    @State private var path: NWPath?

    var body: some View {
        List {
            Section("Current connection") {
                LabeledContent("Network path", value: connectionStatus)
                if let path, path.status == .satisfied {
                    LabeledContent("Connection type", value: interfaceNames(path))
                }
            }
            Section("Wi-Fi security · guided") {
                Text("Open Settings → Wi-Fi and tap the information button beside your network. Look for a Weak Security or Privacy Warning.")
                Text("Kabuto checks the connection type locally. Wi-Fi encryption and the network operator’s identity need your review.")
                    .font(.footnote).foregroundStyle(.secondary)
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

    private var connectionStatus: String {
        guard let path else { return "Checking…" }
        switch path.status {
        case .satisfied: return "Available · verified"
        case .unsatisfied: return "Unavailable · verified"
        case .requiresConnection: return "Connection needed · verified"
        @unknown default: return "Unknown"
        }
    }

    private func interfaceNames(_ path: NWPath) -> String {
        let types: [(NWInterface.InterfaceType, String)] = [(.wifi, "Wi-Fi"), (.cellular, "Cellular"), (.wiredEthernet, "Ethernet")]
        let names = types.filter { path.usesInterfaceType($0.0) }.map { $0.1 }
        return names.isEmpty ? "Other" : names.joined(separator: ", ")
    }
}
