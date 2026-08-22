//
//  HomeView.swift
//  Tsundoku
//

import SwiftUI

struct HomeView: View {
    let authStore: AuthStore
    let articleLibrary: ArticleLibrary
    let subscriptionStore: SubscriptionStore
    @AppStorage(castDefaultDurationKey) private var defaultDuration = 10
    @AppStorage("customDigestDuration") private var customDuration = 20
    @State private var selectedDuration = 10
    @State private var durationSelection = 10
    @State private var isShowingCustomDuration = false
    @State private var isShowingSubscription = false
    @State private var browserDestination: InAppBrowserDestination?
    @State private var recommendationStore = RecommendationStore()
    @State private var peerTrendsStore = PeerTrendsStore()

    private let durations = [5, 10, 15, 20]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    greeting
                    durationPicker
                    // digestCard
                    personalizedNewsSection
                    expiringSection
                    Divider()
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                    PeerTrendsSection(
                        language: .japanese,
                        store: peerTrendsStore,
                        isPaid: subscriptionStore.planTier != .free,
                        onUpgrade: { isShowingSubscription = true }
                    )
                }
                .padding(.horizontal, AppDesign.pagePadding)
                .padding(.top, 20)
                .padding(.bottom, 36)
            }
            .background(Color(.systemGroupedBackground))
            .sheet(isPresented: $isShowingCustomDuration) {
                CustomDurationSheet(language: .japanese, initialDuration: customDuration) { duration in
                    customDuration = duration
                    selectedDuration = duration
                    durationSelection = -1
                }
            }
            .sheet(isPresented: $isShowingSubscription) {
                SubscriptionManagementView(
                    subscriptionStore: subscriptionStore,
                    language: .japanese,
                    initialTier: .plus
                )
            }
            .sheet(item: $browserDestination) { destination in
                InAppBrowserView(url: destination.url)
                    .ignoresSafeArea()
            }
            .task {
                applyDefaultDuration()
                await peerTrendsStore.load(token: authStore.sessionToken())
            }
            .onChange(of: defaultDuration) { _, _ in applyDefaultDuration() }
        }
    }

    private var personalizedNewsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink {
                PersonalNewsFeedScreen(
                    authStore: authStore,
                    articleLibrary: articleLibrary,
                    subscriptionStore: subscriptionStore,
                    language: .japanese,
                    store: recommendationStore
                )
            } label: {
            HStack(spacing: 16) {
                Image(systemName: "newspaper.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(
                        LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 5) {
                    Text("あなたのためのニュース")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("興味やメモリに合わせた今日の5件")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("あなたのためのニュース。今日の5件を見る")

            Divider()
                .padding(.leading, 82)

            PersonalNewsHomePreview(
                authStore: authStore,
                articleLibrary: articleLibrary,
                language: .japanese,
                store: recommendationStore
            )
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.indigo.opacity(0.12), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("StackCast")
                .font(.largeTitle.bold())

            Text(currentDateText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var currentDateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone = .current
        formatter.dateFormat = "M月d日 EEEE"
        return formatter.string(from: .now)
    }

    private var durationPicker: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("今日はどれくらい聴けますか？")
                .font(.headline)

            DurationSegmentedControl(
                selection: $durationSelection,
                durations: durations,
                customDuration: customDuration,
                language: .japanese,
                onCustomize: {
                    if subscriptionStore.isPro {
                        isShowingCustomDuration = true
                    } else {
                        durationSelection = 10
                        selectedDuration = 10
                        isShowingSubscription = true
                    }
                }
            )
            .onChange(of: durationSelection) { _, selection in
                guard subscriptionStore.isPro || selection == 10 else {
                    durationSelection = 10
                    selectedDuration = 10
                    isShowingSubscription = true
                    return
                }

                withAnimation(.snappy) {
                    selectedDuration = selection == -1 ? customDuration : selection
                }
            }
        }
    }

    private func applyDefaultDuration() {
        let duration = subscriptionStore.isPro ? min(20, max(5, defaultDuration)) : 10
        selectedDuration = duration
        if durations.contains(duration) {
            durationSelection = duration
        } else {
            customDuration = duration
            durationSelection = -1
        }
    }

    private var digestCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("TODAY'S DIGEST")
                        .font(.caption.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.75))

                    Text("通勤前の\(selectedDuration)分")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                }

                Spacer()

                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.white)
            }

            Text("音声生成は現在利用できません")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))

            Button {} label: {
                Label("Cast生成は現在利用できません", systemImage: "waveform.badge.exclamationmark")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .foregroundStyle(.indigo)
                    .background(.white, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(true)
        }
        .padding(22)
        .background(
            LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .shadow(color: .indigo.opacity(0.22), radius: 18, y: 10)
    }

    private var expiringSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("期限が近い記事")
                    .font(.title3.bold())
                Spacer()
                Button("すべて見る") {}
                    .font(.caption.weight(.semibold))
            }

            if unreadArticles.isEmpty {
                ContentUnavailableView(
                    "保存した記事はありません",
                    systemImage: "tray",
                    description: Text("Webページの共有から記事を追加できます。")
                )
                .frame(maxWidth: .infinity)
                .tsundokuCard()
            } else {
                VStack(spacing: 18) {
                    ForEach(Array(unreadArticles.prefix(2).enumerated()), id: \.element.id) { index, article in
                        Button {
                            articleLibrary.mark(article.id, as: .inProgress)
                            if let url = article.originalURL {
                                browserDestination = InAppBrowserDestination(url: url)
                            }
                        } label: {
                            ArticleRow(article: article)
                        }
                        .buttonStyle(.plain)

                        if index < min(unreadArticles.count, 2) - 1 {
                            Divider().padding(.leading, 78)
                        }
                    }
                }
                .tsundokuCard()
            }
        }
    }

    private var unreadArticles: [MockArticle] {
        articleLibrary.articles
            .map { $0.displayArticle(language: .japanese) }
            .filter { $0.status == .unread }
    }

}

#Preview {
    HomeView(authStore: AuthStore(), articleLibrary: ArticleLibrary(), subscriptionStore: SubscriptionStore())
}
