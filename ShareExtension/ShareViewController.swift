//
//  ShareViewController.swift
//  ShareExtension
//

import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()

        Task { @MainActor in
            await saveSharedURL()
        }
    }

    private func configureView() {
        view.backgroundColor = .systemBackground
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.text = "ストックに保存中…"
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    @MainActor
    private func saveSharedURL() async {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem else {
            finishWithError()
            return
        }

        let title = extensionItem.attributedContentText?.string
        let providers = extensionItem.attachments ?? []

        for provider in providers {
            if let url = await loadURL(from: provider),
               SharedArticleRepository.save(url: url, title: title) != nil {
                statusLabel.text = "ストックに保存しました"
                try? await Task.sleep(for: .milliseconds(450))
                extensionContext?.completeRequest(returningItems: nil)
                return
            }
        }

        finishWithError()
    }

    private func loadURL(from provider: NSItemProvider) async -> URL? {
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
           let item = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) {
            if let url = item as? URL { return url }
            if let url = item as? NSURL { return url as URL }
            if let text = item as? String { return URL(string: text) }
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
           let item = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier),
           let text = item as? String {
            return firstWebURL(in: text)
        }

        return nil
    }

    private func firstWebURL(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        return detector.firstMatch(in: text, range: range)?.url
    }

    private func finishWithError() {
        statusLabel.text = "WebページのURLを読み取れませんでした"
        statusLabel.textColor = .systemRed

        let error = NSError(
            domain: "com.nexro.Tsundoku.ShareExtension",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "共有された項目にWebページのURLがありません。"]
        )
        extensionContext?.cancelRequest(withError: error)
    }
}
