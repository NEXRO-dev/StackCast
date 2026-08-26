//
//  AIDataUseView.swift
//  Tsundoku
//

import SwiftUI

private let aiArticleProcessingConsentKey = "aiArticleProcessingConsentAccepted"

struct AIDataUseView: View {
    let language: AppLanguage
    @Environment(\.dismiss) private var dismiss
    @AppStorage(aiArticleProcessingConsentKey) private var consentAccepted = false

    private var isEnglish: Bool { language == .english }

    var body: some View {
        ScrollView {
            Text(isEnglish ? englishDisclosure : japaneseDisclosure)
                .font(.body)
                .lineSpacing(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(isEnglish ? "Data Use" : "データ利用")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                if consentAccepted {
                    dismiss()
                    return
                }
                consentAccepted = true
                dismiss()
            } label: {
                Text(consentAccepted
                     ? (isEnglish ? "Consent given" : "同意済み")
                     : (isEnglish ? "Agree and continue" : "同意して続ける"))
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(consentAccepted ? Color(white: 0.36) : Color.accentColor)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(.bar)
        }
    }

    private var japaneseDisclosure: String {
        """
        データ利用について

        本アプリでは、保存した記事を要約し、音声Castとして再生できる形に変換する機能を提供しています。この機能を利用するには、保存した記事の中からCastの対象にする記事をあなた自身で選択し、Cast作成の操作を行う必要があります。

        PlusまたはProプランで「デイリーニュースCastを自動生成」を有効にした場合は、あなたが設定した興味ジャンルとおすすめメモリをもとにバックエンドが毎日5件の記事を選び、個別の作成操作を行わなくても自動的に要約と音声を生成します。この設定はいつでもおすすめ設定から無効にできます。

        Castを作成すると、選択した記事のタイトル・URL・本文が、要約と音声を生成するためにアプリのバックエンドを経由して外部サービスへ送信されます。記事を保存しただけでは、記事本文が外部AIサービスへ送信されることはありません。

        送信先は、記事の要約生成に利用するOpenAIと、要約テキストの音声生成に利用するFish Audioです。OpenAIでは選択した記事の内容をもとに要約テキストを生成し、Fish Audioではその要約テキストを音声データへ変換します。各サービスは、Castを生成してアプリの機能を提供するために送信されたデータを処理します。

        送信されるデータには、記事のタイトル、記事のURL、記事本文、およびCast生成に必要な処理情報が含まれます。アカウントのパスワード、決済情報、認証トークンをAIサービスへ送信することはありません。ただし、記事本文に氏名、メールアドレス、勤務先、健康情報、位置情報、その他の個人情報や第三者に関する情報が含まれている場合、それらが記事本文の一部として送信される可能性があります。

        Castを作成する前に、外部サービスへ送信してよい記事だけを選択してください。第三者の著作物や機密情報を含む記事を送信する場合は、必要な権利や許可を自分で確認してください。本アプリは、あなたが選択した記事を送信することについて、記事の権利者や第三者から許可を取得するものではありません。

        生成された要約、音声、Castの処理状態などは、Castを表示・再生・共有するためにアプリのバックエンドへ保存される場合があります。OpenAIのAPI入力・出力は、明示的にオプトインしない限りモデル学習には利用されませんが、不正利用監視のため最長30日程度保持される場合があります。Fish Audioでは、利用規約により送信した台本や利用データがサービス改善・AIモデルの学習に利用される可能性があり、削除後も一部の記録が残る場合があります。外部サービスの保存期間、学習利用、削除手続きは各サービスのポリシーおよび本アプリのプライバシーポリシーに従います。

        Castを作成しない場合でも、記事の保存、閲覧、削除など本アプリの基本機能は利用できます。同意はCast作成のために必要なものであり、同意しないことによってアカウントを作成できなくなったり、保存済みの記事が削除されたりすることはありません。将来、同意を撤回したい場合は、設定画面またはプライバシーポリシーに記載された方法で手続きを行ってください。

        上記の内容を確認し、選択した記事がOpenAIおよびFish Audioへ送信され、要約と音声の生成に利用されることに同意する場合は、「同意して続ける」を押してください。同意しない場合、または内容について確認したいことがある場合は、同意せずに画面を閉じてください。データ利用に関する質問や削除の依頼は、アプリ内に掲載するサポート窓口からお問い合わせください。
        """
    }

    private var englishDisclosure: String {
        """
        About data use

        This app can summarize saved articles and turn them into audio Casts. To use this feature, you select the articles to include and explicitly start Cast creation. When you create a Cast, the title, URL, and content of the selected articles are sent through the app backend to external services to generate a summary and audio. Saving an article alone does not send its content to an external AI service.

        If you are on Plus or Pro and enable automatic Daily News Casts, the backend selects five articles each day using your chosen interests and recommendation memory. Those articles are summarized and converted to audio automatically without a separate creation action. You can disable automatic creation at any time in Personalization settings.

        OpenAI is used to generate the article summary, and Fish Audio is used to convert the summary into speech. OpenAI receives the selected article content for summarization, and Fish Audio receives the generated summary for text-to-speech processing. OpenAI API inputs and outputs are not used to train models unless the API customer explicitly opts in, but OpenAI may retain data for abuse monitoring for up to approximately 30 days. Under Fish Audio’s terms, submitted scripts and usage data may be used to develop, train, or improve AI models, and some records may remain after deletion. These services process the submitted data to provide the Cast feature.

        The submitted data may include the selected article title, URL, article content, and processing information needed to generate the Cast. Your password, payment information, and authentication tokens are not sent to these AI services. However, if an article contains names, email addresses, employer information, health information, location information, confidential information, or information about another person, that information may be included in the article content sent for processing.

        Please select only articles that you are comfortable sending to these services. If an article contains copyrighted material, confidential information, or another person’s personal information, you are responsible for confirming that you have the necessary rights or permission to submit it. This app does not obtain those permissions on your behalf.

        Generated summaries, audio, and Cast processing information may be stored by the app backend so that you can view, play, and share your Cast. Data handling, retention, model-training practices, and deletion procedures at the external services are governed by their policies and by this app’s Privacy Policy. Please refer to the Privacy Policy for retention periods, account deletion, data deletion requests, and your rights.

        You can continue to save, view, and delete articles without creating a Cast. This consent is required for Cast creation only. Declining consent does not delete your saved articles or prevent you from using the other basic features of the app. To withdraw consent or request deletion, use the method described in the app or in the Privacy Policy.

        By selecting “Agree and continue,” you confirm that you understand and agree that the selected articles will be sent to OpenAI and Fish Audio for summarization and audio generation. If you do not agree, or if you have questions about this processing, close this screen without agreeing and contact support using the method provided in the app.
        """
    }
}

struct AIDataConsentSheet: View {
    let language: AppLanguage

    var body: some View {
        NavigationStack {
            AIDataUseView(language: language)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        DismissButton(language: language)
                    }
                }
        }
    }
}

private struct DismissButton: View {
    let language: AppLanguage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button(language == .english ? "Cancel" : "キャンセル") {
            dismiss()
        }
    }
}
