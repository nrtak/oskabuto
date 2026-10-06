import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        show(nil, message: "Reading the shared link…")
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
                            show(SafetyEngine.check(input), message: "")
                            return
                        }
                    } catch { continue }
                }
            }
            show(nil, message: "Share one link to check it, or paste it into Kabuto’s Link Checker.")
        }
    }
    @MainActor private func show(_ result: SafetyResult?, message: String) {
        for child in children { child.willMove(toParent: nil); child.view.removeFromSuperview(); child.removeFromParent() }
        let host = UIHostingController(rootView: SharedLinkView(result: result, message: message) { [weak self] in
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
    let done: () -> Void
    var body: some View {
        NavigationStack {
            List {
                if let result {
                    Section(result.title) { ForEach(result.reasons, id: \.self) { Text($0) } }
                } else { Text(message) }
                Text("Checked on this device. Nothing opened, uploaded, or saved.").font(.caption).foregroundStyle(.secondary)
            }.navigationTitle("Kabuto Link Check").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", action: done) } }
        }
    }
}
