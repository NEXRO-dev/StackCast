//
//  SupportView.swift
//  Tsundoku
//

import MessageUI
import PhotosUI
import SwiftUI
import UIKit

struct SupportView: View {
    let language: AppLanguage

    @Environment(\.openURL) private var openURL
    @State private var category = SupportCategory.cast
    @State private var message = ""
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var attachments: [MailAttachment] = []
    @State private var isShowingMailComposer = false
    @State private var mailBody = ""

    private let supportEmail = "support@stackcast.app"

    var body: some View {
        Form {
            Section {
                Text(language == .english
                     ? "Tell us what happened and we will help you. Please include the steps that caused the issue and any relevant error message."
                     : "問題の内容を入力して送信してください。発生した手順やエラーメッセージがあると、よりスムーズに対応できます。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section(language == .english ? "Inquiry details" : "お問い合わせ内容") {
                Picker(language == .english ? "Category" : "カテゴリ", selection: $category) {
                    ForEach(SupportCategory.allCases) { category in
                        Text(category.title(language: language)).tag(category)
                    }
                }

                ZStack(alignment: .topLeading) {
                    if message.isEmpty {
                        Text(language == .english
                             ? "Describe the issue or question"
                            : "問題や質問の内容を入力してください")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $message)
                        .frame(minHeight: 140)
                        .scrollContentBackground(.hidden)
                }

                PhotosPicker(
                    selection: $selectedPhotoItems,
                    maxSelectionCount: 3,
                    matching: .images
                ) {
                    Label(
                        language == .english ? "Attach photos (up to 3)" : "写真を添付（最大3枚）",
                        systemImage: "photo"
                    )
                }

                if !attachments.isEmpty {
                    Text(language == .english
                         ? "\(attachments.count) photo(s) selected"
                         : "写真を\(attachments.count)枚選択中")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    openSupportEmail()
                } label: {
                    Label(
                        language == .english ? "Create email" : "メールで問い合わせる",
                        systemImage: "envelope"
                    )
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } footer: {
                Text(language == .english
                     ? "Your email app will open with the inquiry details."
                     : "メールアプリが開き、入力内容とアプリ情報が設定されます。")
            }

            Section(language == .english ? "Support email" : "サポート窓口") {
                Text(supportEmail)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .navigationTitle(language == .english ? "Contact Support" : "サポートに問い合わせ")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selectedPhotoItems) { _, items in
            Task {
                attachments = await loadAttachments(from: items)
            }
        }
        .sheet(isPresented: $isShowingMailComposer) {
            MailComposerView(
                recipient: supportEmail,
                subject: language == .english ? "StackCast Support Request" : "StackCast サポートへの問い合わせ",
                body: mailBody,
                attachments: attachments
            )
        }
    }

    private func openSupportEmail() {
        let body = """
        Category: \(category.title(language: .english))

        \(message.trimmingCharacters(in: .whitespacesAndNewlines))

        App version: \(appVersion)
        """

        mailBody = body

        if MFMailComposeViewController.canSendMail() {
            isShowingMailComposer = true
            return
        }

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        components.queryItems = [
            URLQueryItem(
                name: "subject",
                value: language == .english ? "StackCast Support Request" : "StackCast サポートへの問い合わせ"
            ),
            URLQueryItem(name: "body", value: body)
        ]

        guard let url = components.url else { return }
        openURL(url)
    }

    private func loadAttachments(from items: [PhotosPickerItem]) async -> [MailAttachment] {
        var loaded: [MailAttachment] = []

        for (index, item) in items.enumerated() {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let jpegData = image.jpegData(compressionQuality: 0.82) else { continue }

            loaded.append(
                MailAttachment(
                    data: jpegData,
                    mimeType: "image/jpeg",
                    fileName: "stashcast-photo-\(index + 1).jpg"
                )
            )
        }

        return loaded
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }
}

private struct MailAttachment {
    let data: Data
    let mimeType: String
    let fileName: String
}

private struct MailComposerView: UIViewControllerRepresentable {
    let recipient: String
    let subject: String
    let body: String
    let attachments: [MailAttachment]

    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss)
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let composer = MFMailComposeViewController()
        composer.mailComposeDelegate = context.coordinator
        composer.setToRecipients([recipient])
        composer.setSubject(subject)
        composer.setMessageBody(body, isHTML: false)

        for attachment in attachments {
            composer.addAttachmentData(
                attachment.data,
                mimeType: attachment.mimeType,
                fileName: attachment.fileName
            )
        }

        return composer
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let dismiss: DismissAction

        init(dismiss: DismissAction) {
            self.dismiss = dismiss
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            dismiss()
        }
    }
}

private enum SupportCategory: String, CaseIterable, Identifiable {
    case cast
    case article
    case account
    case billing
    case other

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch (self, language) {
        case (.cast, .english): "Cast generation or playback"
        case (.cast, _): "Castの生成・再生"
        case (.article, .english): "Article saving or reading"
        case (.article, _): "記事の保存・閲覧"
        case (.account, .english): "Account or sign-in"
        case (.account, _): "アカウント・ログイン"
        case (.billing, .english): "Subscription or billing"
        case (.billing, _): "サブスクリプション・課金"
        case (.other, .english): "Other"
        case (.other, _): "その他"
        }
    }
}

#Preview {
    NavigationStack {
        SupportView(language: .japanese)
    }
}
