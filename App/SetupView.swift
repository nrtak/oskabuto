import SwiftUI

enum ProtectionRoute: Hashable {
    case review, device, calls, privacy, messages, web

    @MainActor @ViewBuilder var destination: some View {
        switch self {
        case .review:
            ProtectionReviewView()
        case .device: DeviceSecurityView()
        case .calls: CallsView()
        case .privacy: PrivacyChecksView()
        case .messages: MessageDemoView()
        case .web: DNSView()
        }
    }
}

private struct ProtectionReviewView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        List {
            if state.callFilterEnabled == false {
                Section("Next step") {
                    NavigationLink(value: ProtectionRoute.calls) {
                        VStack(alignment: .leading) {
                            Label("Review call filtering", systemImage: "phone")
                            Text("iOS reports that Call Protection is off. Open setup to enable your saved rules.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("Review checks") {
                NavigationLink(value: ProtectionRoute.device) { Label("Check screen lock", systemImage: "lock") }
                if state.callFilterEnabled != false {
                    NavigationLink(value: ProtectionRoute.calls) { Label("Review call filtering", systemImage: "phone") }
                }
                NavigationLink(value: ProtectionRoute.privacy) { Label("Review browser privacy", systemImage: "safari") }
            }
        }.navigationTitle("Protection Review").navigationBarTitleDisplayMode(.inline)
        .onAppear { state.refreshCalls() }
    }
}

struct ProtectionView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        List {
            Section("Calls & messages") {
                NavigationLink(value: ProtectionRoute.calls) {
                    feature("Call Protection", symbol: "phone.fill", tint: .blue, status: state.callStatus)
                }
                NavigationLink(value: ProtectionRoute.messages) {
                    feature("Message Filter", symbol: "message.fill", tint: .indigo, status: .unverified("Not verified · check Settings"))
                }
            }
            Section("Browsing") {
                NavigationLink(value: ProtectionRoute.web) {
                    feature("Web Protection", symbol: "globe", tint: .teal, detail: "Secure DNS · Quad9, Cloudflare, Google, or custom")
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

    private func feature(_ name: String, symbol: String, tint: Color, detail: String = "", status: CheckStatus? = nil) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(tint)
                .frame(width: 38, height: 38).background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.headline)
                if let status { StatusLabel(status: status).font(.subheadline) }
                else { Text(detail).font(.subheadline).foregroundStyle(.secondary) }
            }
        }.padding(.vertical, 4)
    }
}
