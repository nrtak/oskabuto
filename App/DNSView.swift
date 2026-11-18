import SwiftUI

enum DNSChoice: String, CaseIterable, Identifiable {
    case quad9 = "Quad9 Secure"
    case malware = "Cloudflare Malware Blocking"
    case cloudflare = "Cloudflare 1.1.1.1"
    case system = "System Default"
    case custom = "Custom DNS"
    var id: String { rawValue }
    var endpoint: String {
        switch self {
        case .quad9: return "https://dns.quad9.net/dns-query"
        case .malware: return "https://security.cloudflare-dns.com/dns-query"
        case .cloudflare: return "https://cloudflare-dns.com/dns-query"
        default: return ""
        }
    }
    var explanation: String {
        switch self {
        case .quad9: return "Quad9 can block known harmful domains. It receives the domain names your device looks up."
        case .malware: return "Cloudflare can block known malware domains. It receives the domain names your device looks up."
        case .cloudflare: return "Cloudflare encrypts domain lookups. This option has no malware filter."
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
                Picker("Provider", selection: $stored) { ForEach(DNSChoice.allCases) { Text($0.rawValue).tag($0.rawValue) } }
                Text(choice.explanation)
                if choice == .custom {
                    TextField("https://resolver.example/dns-query", text: $custom)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
            }
            if choice == .system {
                Section("Use System Default") {
                    Text("If you installed Kabuto Web Protection (formerly Kabuto DNS), remove its profile in Settings → General → VPN & Device Management.")
                    Text("Choosing System Default here only changes your selection in Kabuto.").font(.footnote)
                }
            } else {
                Section("2. Create profile") {
                    if let profile {
                        Label("Profile created", systemImage: "checkmark.circle")
                        ShareLink("Export setup profile", item: profile)
                    } else {
                        Button("Create setup profile") {
                            do { profile = try DNSProfile.create(name: choice.rawValue, endpoint: choice == .custom ? custom.trimmingCharacters(in: .whitespacesAndNewlines) : choice.endpoint) }
                            catch { state.notice = error.localizedDescription }
                        }
                    }
                }
                Section("3. Install in Settings") {
                    Text("Export the profile using Save to Files, then open the saved file.")
                    Text("In Settings, tap Profile Downloaded. Review the unsigned Kabuto Web Protection profile and tap Install.")
                    Text("Check the installed profile in Settings → General → VPN & Device Management. You can also remove it there.").font(.footnote)
                    Text("Guided setup. Kabuto cannot confirm which provider is active. Some apps use their own DNS.").font(.footnote).foregroundStyle(.secondary)
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
