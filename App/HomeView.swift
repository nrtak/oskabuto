import SwiftUI

private struct GlassTile: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var interactive = true

    @ViewBuilder func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        if #available(iOS 26, *), !reduceTransparency {
            content.glassEffect(.regular.interactive(interactive), in: shape)
        } else {
            content.background(Color(uiColor: .secondarySystemGroupedBackground), in: shape)
                .overlay { shape.strokeBorder(.secondary.opacity(0.25)) }
        }
    }
}

private struct ProtectionBranches: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let endpoints = [CGPoint(x: rect.width * 0.25, y: rect.minY),
                         CGPoint(x: rect.width * 0.75, y: rect.minY),
                         CGPoint(x: rect.midX, y: rect.maxY)]
        for endpoint in endpoints {
            path.move(to: CGPoint(x: rect.midX, y: rect.midY))
            path.addLine(to: endpoint)
        }
        return path
    }
}

struct HomeView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                VStack(spacing: 0) {
                    tileLayout {
                        tile("Call Directory", "phone.fill", .teal, state.callStatus) { CallsView() }
                        tile("Message Filter", "message.fill", .indigo, "Guided · Settings") { MessageDemoView() }
                    }
                    ZStack {
                        if !textSize.isAccessibilitySize {
                            ProtectionBranches().stroke(.teal, lineWidth: 2).accessibilityHidden(true)
                        }
                        VStack(spacing: 4) {
                            Image("AppMark").resizable().scaledToFit().frame(width: 52, height: 52)
                                .clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityHidden(true)
                            Text("Kabuto Mobile Security").font(.headline).multilineTextAlignment(.center)
                        }
                        .padding(12).modifier(GlassTile(interactive: false)).padding(.vertical, 6)
                        .accessibilityAddTraits(.isHeader)
                    }.fixedSize(horizontal: false, vertical: true)
                    tile("Secure DNS", "network", .blue, "Guided · DNS profile") { DNSView() }
                }
                Text("Guided and unknown statuses need review in Settings.")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                Text("Safety tools").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                tileLayout {
                    tile("Link Checker", "link", .blue) { CheckerView() }
                    tile("QR Scanner", "qrcode.viewfinder", .indigo) { CheckerView(qrMode: true) }
                    tile("Privacy Review", "checklist", .teal) { PrivacyChecksView() }
                }
            }.padding(16)
        }
        .background {
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
            if !reduceTransparency {
                RadialGradient(colors: [.mint.opacity(0.32), .teal.opacity(0.08), .clear],
                               center: .init(x: 0.5, y: 0.32), startRadius: 16, endRadius: 330)
                    .ignoresSafeArea().allowsHitTesting(false)
            }
        }
        .navigationTitle("Home").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink("Set up") { SetupView() }
            }
        }
    }

    private var tileLayout: AnyLayout {
        textSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 10))
    }

    private func tile<Destination: View>(_ title: String, _ symbol: String, _ color: Color,
                                         _ detail: String? = nil, @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink(destination: destination()) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.title2.weight(.semibold)).foregroundStyle(color).accessibilityHidden(true)
                Text(title).font(.subheadline.bold()).foregroundStyle(.primary)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 6).padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: detail == nil ? 70 : 86)
            .modifier(GlassTile()).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
