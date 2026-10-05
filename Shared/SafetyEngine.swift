import Foundation

struct SafetyResult: Equatable {
    let title: String
    let reasons: [String]
    let suspicious: Bool
}

enum SafetyEngine {
    static func check(_ input: String) -> SafetyResult {
        guard let url = URL(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = url.host, !host.isEmpty else {
            return .init(title: "Unverified content", reasons: ["Not a complete HTTP or HTTPS link. QR codes can also contain payment, Wi-Fi, or app commands. Nothing was opened."], suspicious: true)
        }
        var reasons: [String] = []
        if scheme == "http" { reasons.append("Connection is not encrypted with HTTPS.") }
        if url.user != nil || url.password != nil { reasons.append("Embedded credentials can disguise the destination.") }
        if host.contains("xn--") { reasons.append("Internationalized domain: check for look-alike characters.") }
        if host.range(of: #"^(\d{1,3}\.){3}\d{1,3}$"#, options: .regularExpression) != nil || host.contains(":") { reasons.append("Destination is a numeric network address.") }
        if ["bit.ly", "tinyurl.com", "t.co"].contains(host.lowercased()) { reasons.append("Shortened link hides the final destination; redirects are not followed.") }
        return .init(title: reasons.isEmpty ? "No local warning found" : "Review before opening", reasons: ["Destination: \(host)"] + reasons + ["Local checks cannot verify reputation, page contents, or redirects. HTTPS does not prove a site is trustworthy."], suspicious: !reasons.isEmpty)
    }

    static func isJunk(_ body: String) -> Bool {
        let text = body.lowercased()
        let urgent = ["urgent", "immediately", "account suspended", "unpaid toll"].contains { text.contains($0) }
        let request = ["http://", "https://", "gift card", "pay now", "password"].contains { text.contains($0) }
        return urgent && request
    }
}
