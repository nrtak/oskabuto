import SwiftUI

struct HomeView: View {
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                brandHeader

                homeSection("Device Security") {
                    VStack(spacing: 0) {
                        reviewRow("Check this device", detail: "Screen lock · \(UIDevice.current.systemName) \(UIDevice.current.systemVersion) installed", symbol: "iphone") {
                            DeviceSecurityView()
                        }
                        rowDivider
                        reviewRow("Network Check", detail: "Connection type and guided Wi-Fi review", symbol: "wifi") {
                            NetworkCheckView()
                        }
                        rowDivider
                        reviewRow("Privacy Checks", detail: "Browser and app permissions", symbol: "hand.raised") {
                            PrivacyChecksView()
                        }
                    }
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
                }

                homeSection("Safety Tools") {
                    actionLayout {
                        actionCard("Check a link", symbol: "link") { CheckerView() }
                        actionCard("Scan a QR code", symbol: "qrcode.viewfinder") { CheckerView(qrMode: true) }
                    }
                }
            }
            .frame(maxWidth: 620)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var brandHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image("AppMark")
                .resizable().scaledToFit()
                .frame(width: 46, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            Text("Kabuto Mobile Security")
                .font(.largeTitle.bold())
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.horizontal, 10)
        .padding(.top, 24)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .topLeading) {
            Canvas { context, _ in
                let center = CGPoint(x: 49, y: 47)
                for index in 1...5 {
                    let radius = CGFloat(index * 24 + 12)
                    let bounds = CGRect(x: center.x - radius, y: center.y - radius,
                                        width: radius * 2, height: radius * 2)
                    context.stroke(Path(ellipseIn: bounds),
                                   with: .color(.primary.opacity(0.15 - Double(index) * 0.022)),
                                   lineWidth: 1)
                }
            }
            .mask(LinearGradient(stops: [
                .init(color: .black, location: 0.45),
                .init(color: .clear, location: 1)
            ], startPoint: .top, endPoint: .bottom))
            .padding(.leading, -16)
            .accessibilityHidden(true).allowsHitTesting(false)
        }
    }

    private func homeSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 10).accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private var rowDivider: some View {
        Divider().padding(.leading, 66)
    }

    private var actionLayout: AnyLayout {
        textSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
    }

    private func actionCard<Destination: View>(_ title: String, symbol: String,
                                               @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink(destination: destination()) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: symbol).font(.title3.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary)
                }.accessibilityHidden(true)
                Text(title).font(.headline).fixedSize(horizontal: false, vertical: true)
            }
            .padding(14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .modifier(ActionSurface(solid: reduceTransparency)).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func reviewRow<Destination: View>(_ title: String, detail: String, symbol: String,
                                              @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink(destination: destination()) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.body.weight(.semibold))
                    .frame(width: 38, height: 38)
                    .background(Color.primary.opacity(0.06), in: Circle()).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }.fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.secondary).accessibilityHidden(true)
            }
            .padding(.horizontal, 16).padding(.vertical, 13).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

private struct ActionSurface: ViewModifier {
    let solid: Bool

    @ViewBuilder func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20)
        if #available(iOS 26, *), !solid {
            content.glassEffect(.regular.interactive(), in: shape)
        } else {
            content.background(Color(uiColor: .secondarySystemGroupedBackground), in: shape)
        }
    }
}
