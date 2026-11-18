import SwiftUI

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
            Label(result.title, systemImage: result.suspicious ? "exclamationmark.triangle" : "magnifyingglass")
                .font(.headline)
            ForEach(result.reasons, id: \.self) { reason in Text(reason) }
        } header: {
            Text(result.destination != nil ? "Destination" : qrContents == nil ? "Result" : "Scanned contents")
        } footer: {
            Text(result.destination == nil ? "Nothing was opened or activated." : "Kabuto checked the address locally. Site reputation, page contents, and redirects remain unverified.")
        }
    }
}
