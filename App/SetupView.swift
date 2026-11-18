import SwiftUI

struct ProtectionView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        List {
            Section("Calls & messages") {
                NavigationLink { CallsView() } label: {
                    feature("Call Protection", symbol: "phone.fill", tint: .blue, detail: state.callStatus)
                }
                NavigationLink { MessageDemoView() } label: {
                    feature("Message Filter", symbol: "message.fill", tint: .indigo, detail: "Guided · review in Messages settings")
                }
            }
            Section("Browsing") {
                NavigationLink { DNSView() } label: {
                    feature("Web Protection", symbol: "globe", tint: .teal, detail: "Guided · choose a DNS provider")
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
