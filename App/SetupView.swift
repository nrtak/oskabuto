import SwiftUI

struct SetupView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        List {
            Section {
                Text("Choose the protection you want. Guided steps need a check in iPhone Settings; Kabuto cannot verify those settings.").font(.subheadline)
            }
            Section("Your setup") {
                NavigationLink { CallsView() } label: {
                    Label { VStack(alignment: .leading) { Text("Call Protection"); Text(state.callStatus).font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: "phone") }
                }
                NavigationLink { MessageDemoView() } label: { Label("Message Filter · guided", systemImage: "message") }
                NavigationLink { DNSView() } label: { Label("Secure DNS · guided", systemImage: "network") }
                NavigationLink { PrivacyChecksView() } label: { Label("Device privacy · guided", systemImage: "checklist") }
                NavigationLink { SettingsView() } label: { Label("Review reminder & activity", systemImage: "gearshape") }
            }
            Section("Check links from other apps") {
                Text("Tap Share on a link, then choose Check with Kabuto. If it is missing, tap More to add it to your Share menu.")
                Text("Only the shared link is checked locally. Nothing is opened, uploaded, or saved.").font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("Set up Kabuto").navigationBarTitleDisplayMode(.inline)
        .onAppear { state.refreshCalls() }
    }
}
