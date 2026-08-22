//
//  AccountView.swift
//  Tsundoku
//

import SwiftUI

struct AccountView: View {
    let authStore: AuthStore
    let subscriptionStore: SubscriptionStore
    let articleLibrary: ArticleLibrary
    let castStore: CastStore
    let playbackStore: CastPlaybackStore
    let language: AppLanguage
    let openSavedArticles: () -> Void
    let openCastLibrary: (String) -> Void

    @State private var destructiveAction: SettingsDestructiveAction?
    @State private var showsCompactProfile = false
    @State private var recommendationStore = RecommendationStore()
    @State private var isResetMemoryConfirmationPresented = false
    @State private var downloadStore = CastDownloadStore.shared
    @State private var isShowingSubscription = false

    private var isEnglish: Bool { language == .english }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    profileCard
#if DEBUG
                    liveActivityPreviewCard
#endif
                    planCard
                    personalizationCard
                    logCard
                    libraryLinksCard

                    if case .signedIn = authStore.status {
                        accountActions
                    }
                }
                .padding(.horizontal, AppDesign.pagePadding)
                .padding(.top, 18)
                .padding(.bottom, 36)
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { _, offset in
                withAnimation(.easeInOut(duration: 0.2)) {
                    if showsCompactProfile {
                        if offset < 80 {
                            showsCompactProfile = false
                        }
                    } else if offset > 120 {
                        showsCompactProfile = true
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(showsCompactProfile ? "" : (isEnglish ? "Account" : "アカウント"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    compactProfile
                }
                ToolbarItem(placement: .topBarTrailing) {
                    settingsButton
                }
            }
            .alert(item: $destructiveAction) { action in
                destructiveAlert(for: action)
            }
            .confirmationDialog(
                isEnglish ? "Reset recommendation memory?" : "おすすめメモリをリセットしますか？",
                isPresented: $isResetMemoryConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button(isEnglish ? "Reset Memory" : "メモリをリセット", role: .destructive) {
                    Task { await recommendationStore.resetMemory(token: authStore.sessionToken()) }
                }
                Button(isEnglish ? "Cancel" : "キャンセル", role: .cancel) {}
            } message: {
                Text(isEnglish ? "Learned interests and dislikes will be deleted." : "学習した興味や「興味なし」の傾向が削除されます。")
            }
            .fullScreenCover(isPresented: $isShowingSubscription) {
                NavigationStack {
                    SubscriptionManagementView(
                        subscriptionStore: subscriptionStore,
                        language: language,
                        initialTier: .plus,
                        showsUpgradeHeader: false
                    )
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                isShowingSubscription = false
                            } label: {
                                Label(
                                    isEnglish ? "Back" : "戻る",
                                    systemImage: "chevron.left"
                                )
                            }
                        }
                    }
                }
            }
            .task {
                await recommendationStore.load(token: authStore.sessionToken())
            }
            .refreshable {
                await recommendationStore.reload(token: authStore.sessionToken())
                if case .signedIn(let user) = authStore.status {
                    await subscriptionStore.identify(
                        userID: user.id,
                        sessionToken: authStore.sessionToken()
                    )
                }
            }
        }
    }

    private var profileCard: some View {
        VStack(spacing: 8) {
            switch authStore.status {
            case .signedIn(let user):
                AccountAvatarView(user: user)
                    .frame(width: 92, height: 92)
                    .padding(.bottom, 6)
                Text(user.name)
                    .font(.title2.bold())
                Text(user.email)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            case .checking:
                ProgressView()
                Text(isEnglish ? "Checking account…" : "アカウントを確認中…")
                    .foregroundStyle(.secondary)
            case .signedOut:
                Image(systemName: "person.crop.circle.badge.xmark")
                    .font(.system(size: 56))
                    .foregroundStyle(.secondary)
                Text(isEnglish ? "Not signed in" : "ログインしていません")
                    .font(.headline)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var planCard: some View {
        Button {
            isShowingSubscription = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: subscriptionStore.planTier == .free ? "sparkles" : "checkmark.seal.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(subscriptionStore.planTier == .free ? Color.secondary : Color.indigo)
                    .frame(width: 42, height: 42)
                    .background(.indigo.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(isEnglish ? "Current plan" : "現在のプラン")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(subscriptionStore.planTitle(language: language))
                        .font(.headline).foregroundStyle(.primary)
                    Text(isEnglish ? "View or change plan" : "プランを確認・変更")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold)).foregroundStyle(.tertiary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accountCard()
        }
        .buttonStyle(.plain)
    }

#if DEBUG
    private var liveActivityPreviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.indigo)
                    .frame(width: 38, height: 38)
                    .background(.indigo.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(isEnglish ? "Live Activity preview" : "Live Activityプレビュー")
                        .font(.headline)
                    Text(isEnglish ? "Display only. No Cast is generated." : "表示だけの確認用です。Castは生成しません。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Toggle("", isOn: Binding(
                    get: { UserDefaults.standard.bool(forKey: CastGenerationActivityStore.previewEnabledKey) },
                    set: { enabled in
                        UserDefaults.standard.set(enabled, forKey: CastGenerationActivityStore.previewEnabledKey)
                        if enabled {
                            CastGenerationActivityStore.shared.startPreview(language: language)
                        } else {
                            CastGenerationActivityStore.shared.stopPreview()
                        }
                    }
                ))
                .labelsHidden()
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accountCard()
    }
#endif

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.indigo)
                    .frame(width: 42, height: 42)
                    .background(.indigo.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 5) {
                    Text(isEnglish ? "Activity log" : "利用ログ")
                        .font(.headline).foregroundStyle(.primary)
                    Text(isEnglish ? "Articles and Cast activity" : "記事とCastの利用状況")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            Divider()

            Text(isEnglish ? "Articles" : "保存した記事")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 0) {
                accountLogMetric(
                    value: articleLibrary.articles.count,
                    label: isEnglish ? "Saved" : "保存",
                    color: .indigo
                )

                Divider().frame(height: 46)

                accountLogMetric(
                    value: completedArticleCount,
                    label: isEnglish ? "Completed" : "完了",
                    color: .green
                )

                Divider().frame(height: 46)

                accountLogMetric(
                    value: unreadArticleCount,
                    label: isEnglish ? "Unread" : "未消化",
                    color: .orange
                )
            }

            Divider()

            Text("Cast")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 0) {
                accountLogMetric(value: createdCastCount, label: isEnglish ? "Created" : "作成", color: .indigo)
                Divider().frame(height: 46)
                accountLogMetric(value: playedCastCount, label: isEnglish ? "Played" : "再生済み", color: .blue)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accountCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(logSummary)
    }

    private func accountLogMetric(value: Int, label: String, color: Color) -> some View {
        VStack(spacing: 5) {
            Text("\(value)")
                .font(.title2.bold())
                .foregroundStyle(color)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var personalizationCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.indigo)
                    .frame(width: 42, height: 42)
                    .background(.indigo.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(isEnglish ? "Interests & memory" : "興味・おすすめメモリ")
                        .font(.headline).foregroundStyle(.primary)
                    Text(isEnglish ? "Personalizes your daily news" : "毎日のニュースをあなた向けに調整")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                NavigationLink {
                    PersonalizationSettingsView(
                        authStore: authStore,
                        subscriptionStore: subscriptionStore,
                        language: language,
                        store: recommendationStore
                    )
                } label: {
                    Text(isEnglish ? "Edit" : "編集")
                        .font(.subheadline.weight(.semibold))
                }
            }

            Divider()
            memorySectionTitle(isEnglish ? "Interest topics" : "興味ジャンル")
            if !selectedInterestLabels.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(selectedInterestLabels, id: \.self) { label in
                            memoryChip(label, color: .indigo)
                        }
                    }
                }
            } else {
                emptyMemoryText(isEnglish ? "No topics selected" : "ジャンルが未設定です")
            }

            Divider()
            memorySectionTitle(isEnglish ? "Frequently viewed" : "よく見るジャンル")
            memoryRows(positiveMemoryItems, emptyText: isEnglish ? "Learning from your activity" : "利用状況から学習中です", color: .blue)

            Divider()
            memorySectionTitle(isEnglish ? "Not interested" : "興味なしにした傾向")
            memoryRows(negativeMemoryItems, emptyText: isEnglish ? "No disliked trends" : "興味なしの傾向はありません", color: .orange)

            if !recommendationStore.memoryItems.isEmpty {
                Button(role: .destructive) {
                    isResetMemoryConfirmationPresented = true
                } label: {
                    Label(isEnglish ? "Clear recommendation memory" : "おすすめメモリをすべて削除", systemImage: "trash")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accountCard()
    }

    private func memorySectionTitle(_ title: String) -> some View {
        Text(title).font(.subheadline.weight(.semibold))
    }

    private func memoryChip(_ value: String, color: Color) -> some View {
        Text(value)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.1), in: Capsule())
    }

    private func emptyMemoryText(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func memoryRows(_ items: [RecommendationMemoryItem], emptyText: String, color: Color) -> some View {
        if items.isEmpty {
            emptyMemoryText(emptyText)
        } else {
            VStack(spacing: 9) {
                ForEach(items.prefix(4)) { item in
                    HStack(spacing: 10) {
                        memoryChip(memoryDisplayValue(item), color: color)
                        if !item.reason.isEmpty {
                            Text(item.reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Button(role: .destructive) {
                            Task { await recommendationStore.deleteMemory(token: authStore.sessionToken(), id: item.id) }
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isEnglish ? "Delete \(memoryDisplayValue(item))" : "\(memoryDisplayValue(item))を削除")
                    }
                }
            }
        }
    }

    private var settingsButton: some View {
        NavigationLink {
            if isEnglish {
                SettingsViewEN(authStore: authStore, playbackStore: CastPlaybackStore.shared, subscriptionStore: subscriptionStore)
            } else {
                SettingsView(authStore: authStore, playbackStore: CastPlaybackStore.shared, subscriptionStore: subscriptionStore)
            }
        } label: {
            Image(systemName: "gearshape")
                .font(.headline.weight(.semibold))
                .frame(width: 36, height: 36)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isEnglish ? "Settings" : "設定")
    }

    private var libraryLinksCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isEnglish ? "Library" : "ライブラリ")
                .font(.headline)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                accountLibraryButton(
                    title: isEnglish ? "Saved articles" : "保存した記事",
                    symbol: "tray.full",
                    count: articleLibrary.articles.count,
                    action: openSavedArticles
                )
                Divider().padding(.leading, 58)
                accountLibraryButton(
                    title: isEnglish ? "Favorite Casts" : "お気に入り",
                    symbol: "star.fill",
                    count: favoriteCastCount
                ) { openCastLibrary("favorites") }
                Divider().padding(.leading, 58)
                accountLibraryButton(
                    title: isEnglish ? "Downloaded Casts" : "ダウンロード済み",
                    symbol: "arrow.down.circle.fill",
                    count: downloadedCastCount
                ) { openCastLibrary("downloaded") }
            }
            .accountCard()
        }
    }

    private func accountLibraryButton(
        title: String,
        symbol: String,
        count: Int,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.headline)
                    .foregroundStyle(.indigo)
                    .frame(width: 28)
                Text(title).foregroundStyle(.primary)
                Spacer()
                Text("\(count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var compactProfile: some View {
        if showsCompactProfile, case .signedIn(let user) = authStore.status {
            HStack(spacing: 10) {
                AccountAvatarView(user: user)
                    .frame(width: 28, height: 28)
                Text(user.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: 180, alignment: .leading)
            .padding(.horizontal, 8)
            .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .leading)))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(isEnglish ? "Account, \(user.name)" : "アカウント、\(user.name)")
        }
    }

    private var accountActions: some View {
        VStack(spacing: 10) {
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(height: 1)
                .padding(.bottom, 14)

            Button {
                destructiveAction = .logout
            } label: {
                Label(isEnglish ? "Log Out" : "ログアウト", systemImage: "rectangle.portrait.and.arrow.right")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.red, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                destructiveAction = .deleteAccount
            } label: {
                Label(isEnglish ? "Delete Account" : "アカウントを削除", systemImage: "person.crop.circle.badge.minus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 96)
    }

    private var logSummary: String {
        isEnglish
            ? "\(articleLibrary.articles.count) articles saved, \(completedArticleCount) completed, \(createdCastCount) Casts created, \(playedCastCount) played"
            : "記事保存\(articleLibrary.articles.count)件、完了\(completedArticleCount)件、Cast作成\(createdCastCount)件、再生済み\(playedCastCount)件"
    }

    private var positiveMemoryItems: [RecommendationMemoryItem] {
        recommendationStore.memoryItems.filter { $0.polarity.lowercased() == "positive" }
    }

    private var selectedInterestLabels: [String] {
        let topics = recommendationStore.profile?.topics.map { isEnglish ? $0.nameEN : $0.nameJA } ?? []
        let custom = recommendationStore.profile?.customInterests?.map(\.label) ?? []
        return topics + custom
    }

    private var negativeMemoryItems: [RecommendationMemoryItem] {
        recommendationStore.memoryItems.filter { $0.polarity.lowercased() == "negative" }
    }

    private var completedCasts: [CastRecord] {
        castStore.casts.filter { $0.status == "completed" && $0.audioURL != nil }
    }

    private var createdCastCount: Int { completedCasts.count }

    private var playedCastCount: Int {
        completedCasts.filter { !playbackStore.isUnplayed($0) }.count
    }

    private var favoriteCastCount: Int {
        let castIDs = Set(castStore.casts.map(\.id))
        return FavoriteCastStorage.load().intersection(castIDs).count
    }

    private var downloadedCastCount: Int { downloadStore.downloadedCasts.count }

    private func memoryDisplayValue(_ item: RecommendationMemoryItem) -> String {
        guard item.kind == "topic",
              let topic = recommendationStore.topics.first(where: { $0.id == item.value }) else {
            return item.value
        }
        return topic.name(language: language)
    }

    private var completedArticleCount: Int {
        articleLibrary.articles.filter { $0.state == .completed }.count
    }

    private var unreadArticleCount: Int {
        articleLibrary.articles.filter { article in
            let status = article.displayArticle(language: language).status
            return status == .unread || status == .inProgress
        }.count
    }

    private func destructiveAlert(for action: SettingsDestructiveAction) -> Alert {
        switch action {
        case .logout:
            Alert(
                title: Text(isEnglish ? "Log out?" : "ログアウトしますか？"),
                message: Text(isEnglish ? "You will be signed out of your current account." : "現在のアカウントからログアウトします。"),
                primaryButton: .destructive(Text(isEnglish ? "Log Out" : "ログアウト")) { Task { await authStore.logout() } },
                secondaryButton: .cancel(Text(isEnglish ? "Cancel" : "キャンセル"))
            )
        case .deleteAccount:
            Alert(
                title: Text(isEnglish ? "Delete account?" : "アカウントを削除しますか？"),
                message: Text(isEnglish ? "Your account and related data will be permanently deleted. This cannot be undone." : "アカウントと関連するデータは完全に削除され、元に戻せません。"),
                primaryButton: .destructive(Text(isEnglish ? "Delete" : "削除する")) { Task { await deleteAccount() } },
                secondaryButton: .cancel(Text(isEnglish ? "Cancel" : "キャンセル"))
            )
        case .error(let message):
            Alert(title: Text(isEnglish ? "Error" : "エラー"), message: Text(message), dismissButton: .default(Text("OK")))
        }
    }

    private func deleteAccount() async {
        do {
            try await authStore.deleteAccount()
        } catch {
            destructiveAction = .error(isEnglish ? "Could not delete your account. Please try again." : "アカウントを削除できませんでした。もう一度お試しください。")
        }
    }
}

private extension View {
    @ViewBuilder
    func accountCard() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: 24))
        } else {
            self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }
}

#Preview {
    AccountView(
        authStore: AuthStore(),
        subscriptionStore: SubscriptionStore(),
        articleLibrary: ArticleLibrary(),
        castStore: CastStore(),
        playbackStore: .shared,
        language: .japanese,
        openSavedArticles: {},
        openCastLibrary: { _ in }
    )
}
