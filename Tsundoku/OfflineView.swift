//
//  OfflineView.swift
//  Tsundoku
//

import SwiftUI

/// Adds the offline warning without replacing the current screen.
struct OfflineView: ViewModifier {
    let language: AppLanguage
    let isOffline: Bool
    @State private var isPresented = false

    private var isEnglish: Bool { language == .english }

    func body(content: Content) -> some View {
        content
            .alert(isEnglish ? "You're offline" : "オフラインです", isPresented: $isPresented) {
                Button(isEnglish ? "OK" : "確認", role: .cancel) {}
            } message: {
                Text(isEnglish
                     ? "Only saved articles and downloaded Casts are available while offline."
                     : "オフライン中は、保存済みの記事とダウンロード済みのCastのみ利用できます。")
            }
            .onAppear {
                if isOffline { isPresented = true }
            }
            .onChange(of: isOffline) { _, offline in
                if offline { isPresented = true }
            }
    }
}

extension View {
    func offlineWarning(language: AppLanguage, isOffline: Bool) -> some View {
        modifier(OfflineView(language: language, isOffline: isOffline))
    }
}

#Preview("Offline warning - Japanese") {
    Text("ホーム画面")
        .font(.largeTitle.bold())
        .offlineWarning(language: .japanese, isOffline: true)
}

#Preview("Offline warning - English") {
    Text("Home")
        .font(.largeTitle.bold())
        .offlineWarning(language: .english, isOffline: true)
}
