import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        show(nil, message: "Reading shared content…")
        Task { @MainActor in
            let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
            for provider in providers {
                for type in [UTType.url.identifier, UTType.plainText.identifier] where provider.hasItemConformingToTypeIdentifier(type) {
                    do {
                        let value = try await provider.loadItem(forTypeIdentifier: type, options: nil)
                        let input: String?
                        if let url = value as? URL { input = url.absoluteString }
                        else { input = value as? String }
                        if let input, input.utf8.count <= 16384 {
                            let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { continue }
                            let link = SafetyEngine.check(trimmed)
                            if type == UTType.plainText.identifier && (link.destination == nil || trimmed.contains(where: { $0.isWhitespace })) {
                                show(nil, message: "", assessment: SafetyEngine.checkMessage(trimmed))
                            } else {
                                show(link, message: "")
                            }
                            return
                        }
                    } catch { continue }
                }
            }
            show(nil, message: "Share a link or a short message, or paste the text into Kabuto.")
        }
    }
    @MainActor private func show(_ result: SafetyResult?, message: String, assessment: MessageCheck? = nil) {
        for child in children { child.willMove(toParent: nil); child.view.removeFromSuperview(); child.removeFromParent() }
        let host = UIHostingController(rootView: SharedLinkView(result: result, message: message, assessment: assessment) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        })
        addChild(host); view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([host.view.topAnchor.constraint(equalTo: view.topAnchor), host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor), host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor), host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)])
        host.didMove(toParent: self)
    }
}

private struct SharedLinkView: View {
    let result: SafetyResult?
    let message: String
    let assessment: MessageCheck?
    let done: () -> Void
    var body: some View {
        NavigationStack {
            List {
                if let result {
                    CheckResultSection(result: result)
                } else if let assessment {
                    MessageResultSection(result: assessment)
                } else { Text(message) }
            }.navigationTitle("Check with Kabuto").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", action: done) } }
        }
    }
}
