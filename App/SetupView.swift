import SwiftUI

struct ProtectionView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        List {
            Section {
                Text("Choose the protection you want. Guided steps need a check in iPhone Settings; Kabuto cannot verify those settings.").font(.subheadline)
            }
            Section("Protection settings") {
                NavigationLink { CallsView() } label: {
                    Label { VStack(alignment: .leading) { Text("Call Protection"); Text(state.callStatus).font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: "phone") }
                }
                NavigationLink { MessageDemoView() } label: { Label("Message Filter · guided", systemImage: "message") }
                NavigationLink { DNSView() } label: { Label("Web Protection · guided", systemImage: "globe") }
            }
        }.navigationTitle("Protection").navigationBarTitleDisplayMode(.inline)
        .onAppear { state.refreshCalls() }
    }
}
