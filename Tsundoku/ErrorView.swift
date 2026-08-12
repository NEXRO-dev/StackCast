//
//  ErrorView.swift
//  Tsundoku
//

import SwiftUI

enum AppErrorMessage {
    static func title(language: AppLanguage) -> String {
        language == .english ? "Error" : "エラー"
    }

    static func generic(language: AppLanguage) -> String {
        language == .english
            ? "Something went wrong. Please try again."
            : "エラーが発生しました。もう一度お試しください。"
    }

    static func cast(language: AppLanguage, code: String?) -> String {
        switch code {
        case "content_not_allowed":
            return language == .english ? "For safety reasons, this content cannot be converted into a Cast. Article saving is still available. Please select different articles." : "安全上の理由により、この内容はCastに変換できません。記事の保存は引き続き利用できます。別の記事を選択してください。"
        case "moderation_unavailable":
            return language == .english ? "Content safety screening is temporarily unavailable. Please try again later." : "コンテンツの安全確認が一時的に利用できません。時間をおいて再試行してください。"
        case "insufficient_credits":
            return language == .english ? "You do not have enough Cast credits for this request." : "このCastを作成するためのクレジットが不足しています。"
        case "invalid_sources":
            return language == .english ? "Select the required number of articles before creating a Cast." : "必要な件数の記事を選択してからCastを作成してください。"
        case "ai_generation_failed":
            return language == .english ? "The AI summary could not be generated. Please try again later." : "AI要約を生成できませんでした。時間をおいて再試行してください。"
        case "audio_generation_failed":
            return language == .english ? "The audio could not be generated. Please try again later." : "音声を生成できませんでした。時間をおいて再試行してください。"
        case "source_fetch_failed":
            return language == .english ? "One of the selected articles could not be read. Please try different articles." : "選択した記事の一つを読み取れませんでした。別の記事を選択してください。"
        default:
            return generic(language: language)
        }
    }

    static func ok(language: AppLanguage) -> String {
        language == .english ? "OK" : "確認"
    }
}

extension View {
    func appErrorAlert(
        isPresented: Binding<Bool>,
        language: AppLanguage,
        message: String? = nil,
        onDismiss: (() -> Void)? = nil
    ) -> some View {
        alert(AppErrorMessage.title(language: language), isPresented: isPresented) {
            Button(AppErrorMessage.ok(language: language), role: .cancel) {
                onDismiss?()
            }
        } message: {
            Text(message ?? AppErrorMessage.generic(language: language))
        }
    }
}

private struct ErrorAlertPreviewHost: View {
    let language: AppLanguage
    @State private var isPresented = true

    var body: some View {
        Color(.systemGroupedBackground)
            .ignoresSafeArea()
            .appErrorAlert(isPresented: $isPresented, language: language)
    }
}

#Preview("Japanese Alert") {
    ErrorAlertPreviewHost(language: .japanese)
}

#Preview("English Alert") {
    ErrorAlertPreviewHost(language: .english)
}

struct ErrorView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ErrorAlertPreviewHost(language: .japanese)
                .previewDisplayName("Japanese Alert")
            ErrorAlertPreviewHost(language: .english)
                .previewDisplayName("English Alert")
        }
    }
}
