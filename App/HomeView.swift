import SwiftUI

struct HomeView: View {
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let ice = Color(red: 0.81, green: 0.90, blue: 0.97)
    private let navy = Color(red: 0.07, green: 0.15, blue: 0.24)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                deviceCard
                homeSection("Before you open") {
                    actionLayout {
                        actionCard("Check a link", detail: "Inspect a URL", symbol: "link", tint: .blue) { CheckerView() }
                        actionCard("Scan a QR code", detail: "Preview its contents", symbol: "qrcode.viewfinder", tint: .indigo) { CheckerView(qrMode: true) }
                    }
                }
                homeSection("Device Security") {
                    VStack(spacing: 0) {
                        reviewRow("Network Check", detail: "Connection type and Wi-Fi security", symbol: "wifi", tint: .teal) { NetworkCheckView() }
                        Divider().padding(.leading, 68)
                        reviewRow("Privacy Checks", detail: "Browser and app permissions", symbol: "hand.raised", tint: .purple) { PrivacyChecksView() }
                    }
                    .modifier(ActionSurface(solid: reduceTransparency, cornerRadius: 22, interactive: false))
                }
            }
            .frame(maxWidth: 620)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Kabuto Mobile Security").navigationBarTitleDisplayMode(.inline)
    }

    private func homeSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title3.bold()).accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private var deviceCard: some View {
        NavigationLink { DeviceSecurityView() } label: {
            VStack(alignment: .leading, spacing: 14) {
                actionLayout {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Your device").font(.title.bold())
                        Text("\(UIDevice.current.systemName) \(UIDevice.current.systemVersion) installed")
                            .font(.subheadline.weight(.medium)).foregroundStyle(ice)
                        Text("Check your screen lock and software updates.")
                            .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    ZStack {
                        Circle().stroke(ice.opacity(0.28), lineWidth: 1)
                        Circle().inset(by: 8).stroke(ice.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                        Image("AppMark").resizable().scaledToFit().frame(width: 65, height: 65)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .frame(width: 100, height: 100).accessibilityHidden(true)
                }
                HStack {
                    Text("Check this device").font(.headline)
                    Spacer()
                    Image(systemName: "arrow.right").accessibilityHidden(true)
                }
                .padding(.horizontal, 16).frame(minHeight: 44)
                .foregroundStyle(navy)
                .modifier(ActionSurface(solid: reduceTransparency, cornerRadius: 13, tint: ice))
            }
            .padding(18).foregroundStyle(.white)
            .background {
                LinearGradient(colors: [navy, Color(red: 0.15, green: 0.26, blue: 0.40)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private var actionLayout: AnyLayout {
        textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
    }

    private func actionCard<Destination: View>(_ title: String, detail: String, symbol: String, tint: Color,
                                               @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink(destination: destination()) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: symbol).font(.title2.bold()).foregroundStyle(tint)
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.caption.bold()).foregroundStyle(.secondary)
                }.accessibilityHidden(true)
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .modifier(ActionSurface(solid: reduceTransparency)).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func reviewRow<Destination: View>(_ title: String, detail: String, symbol: String, tint: Color,
                                              @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink(destination: destination()) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.title3.weight(.semibold)).foregroundStyle(tint)
                    .frame(width: 40, height: 40).background(tint.opacity(0.12), in: Circle()).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary).accessibilityHidden(true)
            }
            .padding(.horizontal, 15).padding(.vertical, 12).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

private struct ActionSurface: ViewModifier {
    let solid: Bool
    var cornerRadius: CGFloat = 20
    var tint: Color? = nil
    var interactive = true

    @ViewBuilder func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        if #available(iOS 26, *), !solid {
            content.glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            content.background(tint ?? Color(uiColor: .secondarySystemGroupedBackground), in: shape)
        }
    }
}
