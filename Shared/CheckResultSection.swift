import SwiftUI

enum CheckStatus: Equatable {
    case verified(String), attention(String), unverified(String), pending(String)

    var text: String {
        switch self {
        case .verified(let value), .attention(let value), .unverified(let value), .pending(let value): return value
        }
    }
}

struct StatusLabel: View {
    let status: CheckStatus
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let symbol: String
        let color: Color
        switch status {
        case .verified:
            symbol = "checkmark.circle.fill"
            color = scheme == .dark ? .green : Color(red: 0.05, green: 0.40, blue: 0.21)
        case .attention, .unverified:
            symbol = "xmark.circle.fill"
            color = scheme == .dark ? Color(red: 1, green: 0.48, blue: 0.45) : Color(red: 0.69, green: 0.13, blue: 0.15)
        case .pending:
            symbol = "clock"
            color = .secondary
        }
        return Label(status.text, systemImage: symbol).foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct SettingsSteps: View {
    let steps: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(steps.indices, id: \.self) { index in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(index + 1).").fontWeight(.semibold).monospacedDigit()
                    Text(steps[index]).fixedSize(horizontal: false, vertical: true)
                }.accessibilityElement(children: .combine)
            }
        }.padding(.vertical, 4)
    }
}

struct MessageResultSection: View {
    let result: MessageCheck

    var body: some View {
        Section("Message check") {
            StatusLabel(status: result.matchesJunkRule ? .attention("Possible scam") : .unverified("Sender not verified"))
                .font(.headline)
            if result.urgency == nil && result.request == nil { Text("No local warning found.") }
            if let phrase = result.urgency { Text("Urgency cue · “\(phrase)”") }
            if let phrase = result.request {
                Text(phrase.hasSuffix("://") ? "Contains a web link." : "Sensitive request cue · “\(phrase)”")
            }
            Text(result.advice)
        }
    }
}

struct CheckResultSection: View {
    let result: SafetyResult
    var qrContents: String? = nil

    var body: some View {
        Section {
            if let domain = result.destination {
                Text(verbatim: domain)
                    .font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("resultDomain")
            } else if let qrContents {
                let excerpt = qrContents.prefix(240)
                Text(verbatim: String(excerpt) + (excerpt.endIndex < qrContents.endIndex ? "…" : ""))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("qrTextPreview")
            }
            StatusLabel(status: result.suspicious ? .attention(result.title) : .unverified("Site safety not verified")).font(.headline)
            if !result.suspicious { Text(result.title) }
            ForEach(result.reasons, id: \.self) { reason in Text(reason) }
        } header: {
            Text(result.destination != nil ? "Destination" : qrContents == nil ? "Result" : "Scanned contents")
        } footer: {
            Text(result.destination == nil ? "Nothing was opened or activated." : "Kabuto checked the address locally. Site reputation, page contents, and redirects remain unverified.")
        }
    }
}
