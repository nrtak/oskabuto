import SwiftUI

enum ProtectionRoute: Hashable {
    case review, device, calls, privacy, messages, web

    @MainActor @ViewBuilder var destination: some View {
        switch self {
        case .review:
            List {
                NavigationLink(value: Self.device) { Label("Check screen lock", systemImage: "lock") }
                NavigationLink(value: Self.calls) { Label("Review call filtering", systemImage: "phone") }
                NavigationLink(value: Self.privacy) { Label("Review browser privacy", systemImage: "safari") }
            }
            .navigationTitle("Protection Review").navigationBarTitleDisplayMode(.inline)
        case .device: DeviceSecurityView()
        case .calls: CallsView()
        case .privacy: PrivacyChecksView()
        case .messages: MessageDemoView()
        case .web: DNSView()
        }
    }
}

struct ProtectionView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        List {
            Section("Calls & messages") {
                NavigationLink(value: ProtectionRoute.calls) {
                    feature("Call Protection", symbol: "phone.fill", tint: .blue, detail: state.callStatus)
                }
                NavigationLink(value: ProtectionRoute.messages) {
                    feature("Message Filter", symbol: "message.fill", tint: .indigo, detail: "Guided · review in Messages settings")
                }
            }
            Section("Browsing") {
                NavigationLink(value: ProtectionRoute.web) {
                    feature("Web Protection", symbol: "globe", tint: .teal, detail: "Guided · choose a DNS provider")
                }
            }
            Section {
                NavigationLink(value: ProtectionRoute.review) {
                    Label("Protection Review", systemImage: "checklist")
                }
            }
        }
        .navigationTitle("Protection").navigationBarTitleDisplayMode(.inline)
        .onAppear { state.refreshCalls() }
    }

    private func feature(_ name: String, symbol: String, tint: Color, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(tint)
                .frame(width: 38, height: 38).background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 4)
    }
}
