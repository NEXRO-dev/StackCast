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

    static func ok(language: AppLanguage) -> String {
        language == .english ? "OK" : "確認"
    }
}

extension View {
    func appErrorAlert(
        isPresented: Binding<Bool>,
        language: AppLanguage,
        onDismiss: (() -> Void)? = nil
    ) -> some View {
        alert(AppErrorMessage.title(language: language), isPresented: isPresented) {
            Button(AppErrorMessage.ok(language: language), role: .cancel) {
                onDismiss?()
            }
        } message: {
            Text(AppErrorMessage.generic(language: language))
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
