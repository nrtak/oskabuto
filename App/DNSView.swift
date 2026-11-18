import SwiftUI

enum DNSChoice: String, CaseIterable, Identifiable {
    case quad9 = "Quad9 Secure"
    case malware = "Cloudflare Malware Blocking"
    case cloudflare = "Cloudflare 1.1.1.1"
    case google = "Google Public DNS"
    case system = "System Default"
    case custom = "Custom DNS"
    var id: String { rawValue }
    var endpoint: String {
        switch self {
        case .quad9: return "https://dns.quad9.net/dns-query"
        case .malware: return "https://security.cloudflare-dns.com/dns-query"
        case .cloudflare: return "https://cloudflare-dns.com/dns-query"
        case .google: return "https://dns.google/dns-query"
        default: return ""
        }
    }
    var explanation: String {
        switch self {
        case .quad9: return "Quad9 can block known harmful domains. It receives the domain names your device looks up."
        case .malware: return "Cloudflare can block known malware domains. It receives the domain names your device looks up."
        case .cloudflare: return "Cloudflare encrypts domain lookups. This option has no malware filter."
        case .google: return "Google receives and encrypts your DNS lookups in transit. This is a general-purpose resolver."
        case .system: return "Use the provider chosen by your device or network. Filtering depends on that provider."
        case .custom: return "Enter a DNS-over-HTTPS address from a provider you trust. It receives the domain names your device looks up."
        }
    }
}

struct DNSView: View {
    @EnvironmentObject var state: AppState
    @AppStorage("dnsChoice") private var stored = DNSChoice.system.rawValue
    @AppStorage("dnsCustom") private var custom = ""
    @State private var profile: URL?
    private var choice: DNSChoice { DNSChoice(rawValue: stored) ?? .system }
    var body: some View {
        Form {
            Section("1. Choose provider") {
                ForEach(DNSChoice.allCases) { option in
                    Button {
                        stored = option.rawValue
                    } label: {
                        HStack {
                            Text(option.rawValue).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: choice == option ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(choice == option ? Color.accentColor : .secondary)
                                .accessibilityHidden(true)
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(choice == option ? .isSelected : [])
                }
                Text(choice.explanation)
                if choice == .custom {
                    TextField("https://resolver.example/dns-query", text: $custom)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
            }
            if choice == .system {
                Section("Use System Default") {
                    Text("If a Kabuto profile is installed, remove it to return to system DNS.")
                    DisclosureGroup("Check in Settings") {
                        SettingsSteps(steps: ["Open General in Settings.", "Tap VPN & Device Management.", "Select Kabuto Web Protection or Kabuto DNS and tap Remove Profile."])
                    }
                }
            } else {
                Section("2. Create profile") {
                    if let profile {
                        StatusLabel(status: .verified("Profile created"))
                        ShareLink("Export setup profile", item: profile)
                    } else {
                        Button("Create setup profile") {
                            do { profile = try DNSProfile.create(name: choice.rawValue, endpoint: choice == .custom ? custom.trimmingCharacters(in: .whitespacesAndNewlines) : choice.endpoint) }
                            catch { state.notice = error.localizedDescription }
                        }
                    }
                }
                Section("3. Install in Settings") {
                    StatusLabel(status: .unverified("Active provider not verified"))
                    SettingsSteps(steps: ["Export using Save to Files.", "Open the saved profile.", "In Settings, tap Profile Downloaded.", "Review the unsigned Kabuto profile and tap Install."])
                }
            }
        }.navigationTitle("Web Protection")
        .onChange(of: stored) { _, _ in profile = nil }
        .onChange(of: custom) { _, _ in profile = nil }
    }
}

enum DNSProfile {
    static func create(name: String, endpoint: String) throws -> URL {
        guard let url = URL(string: endpoint), url.scheme == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.fragment == nil, url.query == nil else {
            throw NSError(domain: "DNSProfile", code: 1, userInfo: [NSLocalizedDescriptionKey: "Enter an HTTPS DNS endpoint without credentials, query tokens, or a fragment."])
        }
        let payload: [String: Any] = [
            "PayloadType": "com.apple.dnsSettings.managed", "PayloadVersion": 1,
            "PayloadIdentifier": "com.example.privacyguard.dns.settings", "PayloadUUID": UUID().uuidString,
            "PayloadDisplayName": name,
            "DNSSettings": ["DNSProtocol": "HTTPS", "ServerURL": url.absoluteString]
        ]
        let container: [String: Any] = [
            "PayloadType": "Configuration", "PayloadVersion": 1,
            "PayloadIdentifier": "com.example.privacyguard.dns", "PayloadUUID": UUID().uuidString,
            "PayloadDisplayName": "Kabuto Web Protection", "PayloadDescription": "User-selected encrypted DNS. Remove this profile to restore network DNS.",
            "PayloadContent": [payload]
        ]
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("Kabuto Web Protection.mobileconfig")
        try PropertyListSerialization.data(fromPropertyList: container, format: .xml, options: 0).write(to: file, options: [.atomic, .completeFileProtection])
        return file
    }
}
