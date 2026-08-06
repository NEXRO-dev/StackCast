//
//  SettingsView.swift
//  Tsundoku
//

import SwiftUI

struct SettingsView: View {
    let authStore: AuthStore

    @AppStorage(AppLanguage.storageKey) private var appLanguage = AppLanguage.japanese.rawValue
    @State private var notificationsEnabled = true
    @State private var defaultDuration = 10
    @State private var defaultSpeed = 1.0
    @State private var isShowingPro = false

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                languageSection
                planSection
                playbackSection
                notificationSection
                supportSection
                appSection
            }
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .sheet(isPresented: $isShowingPro) {
                ProPlanSheet()
            }
        }
    }

    private var languageSection: some View {
        Section("言語") {
            Picker("表示言語", selection: $appLanguage) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.displayName).tag(language.rawValue)
                }
            }
        }
    }

    private var planSection: some View {
        Section {
            Button {
                isShowingPro = true
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                        Image(systemName: "sparkles")
                            .foregroundStyle(.white)
                    }
                    .frame(width: 52, height: 52)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Freeプラン")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("Proでもっと自由に消化する")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            Button("購入を復元", systemImage: "arrow.clockwise") {}
        } header: {
            Text("プラン")
        }
    }

    private var playbackSection: some View {
        Section("ダイジェスト") {
            Picker("既定の時間", selection: $defaultDuration) {
                ForEach([5, 10, 15, 30], id: \.self) { duration in
                    Text("\(duration)分").tag(duration)
                }
            }

            Picker("既定の再生速度", selection: $defaultSpeed) {
                ForEach([1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                    Text("\(speed.formatted())x").tag(speed)
                }
            }
        }
    }

    private var notificationSection: some View {
        Section {
            Toggle("期限が近い記事を通知", isOn: $notificationsEnabled)
        } header: {
            Text("通知")
        } footer: {
            Text("期限まで24時間以内の記事があるときにお知らせします。")
        }
    }

    private var supportSection: some View {
        Section("サポート") {
            NavigationLink {
                ContentUnavailableView("準備中です", systemImage: "hammer")
            } label: {
                Label("使い方", systemImage: "questionmark.circle")
            }
            Link(destination: URL(string: "https://example.com/terms")!) {
                Label("利用規約", systemImage: "doc.text")
            }
            Link(destination: URL(string: "https://example.com/privacy")!) {
                Label("プライバシーポリシー", systemImage: "hand.raised")
            }
        }
    }

    private var appSection: some View {
        Section("アプリ情報") {
            LabeledContent("バージョン", value: appVersion)
            LabeledContent("保存期限", value: "5日間")
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "1.0.0"
    }

    private var accountSection: some View {
        Section("アカウント") {
            switch authStore.status {
            case .signedIn(let user):
                HStack(spacing: 14) {
                    AccountAvatarView(user: user)
                    .frame(width: 48, height: 48)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("ログイン中")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(user.name)
                            .font(.headline)
                        Text(user.email)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .textSelection(.enabled)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)

            case .checking:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("アカウントを確認中…")
                        .foregroundStyle(.secondary)
                }

            case .signedOut:
                Label("ログインしていません", systemImage: "person.crop.circle.badge.xmark")
                    .foregroundStyle(.secondary)
            }

            if case .signedIn = authStore.status {
                Button("ログアウト", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    Task {
                        await authStore.logout()
                    }
                }
            }
        }
    }
}

private struct ProPlanSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 54))
                        .foregroundStyle(.indigo)
                        .padding(24)
                        .background(.indigo.opacity(0.12), in: Circle())

                    VStack(spacing: 8) {
                        Text("StashCast Pro")
                            .font(.largeTitle.bold())
                        Text("保存も音声ダイジェストも、\n上限を気にせず利用できます。")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        proFeature("保存件数の上限を緩和", symbol: "tray.full")
                        proFeature("すべてのダイジェスト時間", symbol: "clock")
                        proFeature("バックグラウンド再生", symbol: "headphones")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .tsundokuCard()

                    Button("プランを見る") {}
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                }
                .padding(24)
            }
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func proFeature(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.headline)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.indigo)
    }
}

#Preview {
    SettingsView(authStore: AuthStore())
}
