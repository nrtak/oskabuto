import Foundation

struct SafetyResult: Equatable {
    let destination: String?
    let title: String
    let reasons: [String]
    let suspicious: Bool
}

struct MessageCheck {
    let urgency: String?
    let request: String?
    var matchesJunkRule: Bool { urgency != nil && request != nil }

    var advice: String {
        if request == "password" { return "Open the service’s official app to check your account. Keep your password private." }
        if request == "gift card" { return "Verify the request with the person using a phone number you already know before buying a card." }
        if request != nil || urgency != nil { return "Open the organization’s official app or contact it using a number you already know." }
        return "These local checks cannot verify the sender. Confirm unexpected requests through a familiar channel."
    }
}

enum SafetyEngine {
    static func check(_ input: String) -> SafetyResult {
        guard let url = URL(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = url.host, !host.isEmpty else {
            return .init(destination: nil, title: "Unverified content", reasons: ["This content has no complete HTTP or HTTPS destination."], suspicious: true)
        }
        var reasons: [String] = []
        if scheme == "http" { reasons.append("Connection is not encrypted with HTTPS.") }
        if url.user != nil || url.password != nil { reasons.append("Embedded credentials can disguise the destination.") }
        if host.contains("xn--") { reasons.append("Internationalized domain: check for look-alike characters.") }
        if host.range(of: #"^(\d{1,3}\.){3}\d{1,3}$"#, options: .regularExpression) != nil || host.contains(":") { reasons.append("Destination is a numeric network address.") }
        if ["bit.ly", "tinyurl.com", "t.co"].contains(host.lowercased()) { reasons.append("Shortened link hides the final destination; redirects are not followed.") }
        return .init(destination: host, title: reasons.isEmpty ? "No local warning found" : "Review before opening", reasons: reasons, suspicious: !reasons.isEmpty)
    }

    static func checkMessage(_ body: String) -> MessageCheck {
        let text = body.lowercased()
        let urgency = ["urgent", "immediately", "account suspended", "unpaid toll"].first { text.contains($0) }
        let request = ["password", "gift card", "pay now", "https://", "http://"].first { text.contains($0) }
        return MessageCheck(urgency: urgency, request: request)
    }

    static func isJunk(_ body: String) -> Bool { checkMessage(body).matchesJunkRule }
}
