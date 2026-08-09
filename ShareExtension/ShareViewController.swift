//
//  ShareViewController.swift
//  ShareExtension
//

import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let statusLabel = UILabel()
    private let upgradeButton = UIButton(type: .system)

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

        upgradeButton.translatesAutoresizingMaskIntoConstraints = false
        upgradeButton.setTitle("アプリでプランを確認", for: .normal)
        upgradeButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        upgradeButton.isHidden = true
        upgradeButton.addTarget(self, action: #selector(openSubscription), for: .touchUpInside)
        view.addSubview(upgradeButton)

        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -24),
            upgradeButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 16),
            upgradeButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
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
            if let url = await loadURL(from: provider) {
                switch SharedArticleRepository.saveWithLimit(url: url, title: title) {
                case .saved:
                    statusLabel.text = "ストックに保存しました"
                    try? await Task.sleep(for: .milliseconds(450))
                    extensionContext?.completeRequest(returningItems: nil)
                    return
                case .limitReached:
                    statusLabel.text = "Freeプランではストックは10件までです。\nアプリでプランを変更できます。"
                    upgradeButton.isHidden = false
                    return
                case .invalidURL, .failed:
                    continue
                }
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

    @objc private func openSubscription() {
        guard let url = URL(string: "stashcast://subscription") else { return }
        extensionContext?.open(url) { [weak self] _ in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
