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
        case .quad9: return "Encrypted resolver with known malicious-domain blocking. DNS queries go to Quad9 under its privacy policy."
        case .malware: return "Encrypted resolver with malware blocking. DNS queries go to Cloudflare under its privacy policy."
        case .cloudflare: return "Encrypted resolver without malware blocking. DNS queries go to Cloudflare under its privacy policy."
        case .system: return "Use your network's resolver after removing this app's DNS profile. Other profiles or VPNs may still override DNS."
        case .custom: return "HTTPS DNS-over-HTTPS endpoint only. Your chosen provider receives DNS queries; check its trust and privacy policy."
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
            Section("Preferred resolver • not verified active") {
                Picker("Provider", selection: $stored) { ForEach(DNSChoice.allCases) { Text($0.rawValue).tag($0.rawValue) } }
                Text(choice.explanation)
                if choice == .custom { TextField("https://resolver.example/dns-query", text: $custom).textInputAutocapitalization(.never).autocorrectionDisabled() }
            }
            Section("Guided installation") {
                if choice == .system {
                    Text("Remove any Kabuto DNS profile in Settings → General → VPN & Device Management. Selecting System Default here does not change system DNS.")
                } else {
                    Button("Prepare DNS profile") {
                        do { profile = try DNSProfile.create(name: choice.rawValue, endpoint: choice == .custom ? custom : choice.endpoint) }
                        catch { state.notice = error.localizedDescription }
                    }
                    if let profile { ShareLink("Export DNS profile", item: profile) }
                    Text("Export to Files, open the .mobileconfig file, then approve installation in Settings. The profile is unsigned and contains only the selected encrypted DNS endpoint. Inspect it before installing. Remove it to undo.")
                }
                Text("Guided: installation and active resolver are not verified. VPNs, network policy, and apps using their own DNS may affect coverage. DNS protects domain resolution, not all links or traffic.").font(.caption)
            }
            Section("Native integration stub") { Text("A future native setup can use NEDNSSettingsManager after signing with the DNS Settings Network Extension entitlement. This MVP exports a user-installed profile and never installs one silently.") }
        }.navigationTitle("Secure DNS")
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
            "PayloadDisplayName": "Kabuto DNS", "PayloadDescription": "User-selected encrypted DNS. Remove this profile to restore network DNS.",
            "PayloadContent": [payload]
        ]
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("PrivacyGuard-DNS.mobileconfig")
        try PropertyListSerialization.data(fromPropertyList: container, format: .xml, options: 0).write(to: file, options: [.atomic, .completeFileProtection])
        return file
    }
}
