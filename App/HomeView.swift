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

private struct ToolBranches: Shape {
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
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { viewport in
            ScrollView {
                VStack(spacing: 0) {
                    tileLayout {
                        tile("Check a link", "link", .blue) { CheckerView() }
                        tile("Scan a QR code", "qrcode.viewfinder", .indigo) { CheckerView(qrMode: true) }
                    }
                    ZStack {
                        if !textSize.isAccessibilitySize {
                            ToolBranches().stroke(.teal.opacity(0.65), lineWidth: 2)
                                .allowsHitTesting(false).accessibilityHidden(true)
                        }
                        VStack(spacing: 8) {
                            Image("AppMark").resizable().scaledToFit().frame(width: 72, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 17)).accessibilityHidden(true)
                            Text("Kabuto Mobile Security").font(.headline).multilineTextAlignment(.center)
                        }
                        .padding(14).modifier(GlassTile(interactive: false)).padding(.vertical, 24)
                        .accessibilityAddTraits(.isHeader)
                    }.fixedSize(horizontal: false, vertical: true)
                    tile("Review privacy", "checklist", .teal) { PrivacyChecksView() }
                        .frame(maxWidth: textSize.isAccessibilitySize ? .infinity : 200)
                }
                .padding(20)
                .frame(maxWidth: .infinity, minHeight: viewport.size.height)
            }
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
    }

    private var tileLayout: AnyLayout {
        textSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 10))
    }

    private func tile<Destination: View>(_ title: String, _ symbol: String, _ color: Color,
                                         @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink(destination: destination()) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.title2.weight(.semibold)).foregroundStyle(color).accessibilityHidden(true)
                Text(title).font(.subheadline.bold()).foregroundStyle(.primary)
            }
            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 6).padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 88)
            .modifier(GlassTile()).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
