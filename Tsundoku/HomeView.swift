//
//  HomeView.swift
//  Tsundoku
//

import SwiftUI

struct HomeView: View {
    let articleLibrary: ArticleLibrary
    let subscriptionStore: SubscriptionStore
    @AppStorage("customDigestDuration") private var customDuration = 20
    @State private var selectedDuration = 10
    @State private var durationSelection = 10
    @State private var isShowingCustomDuration = false
    @State private var isShowingSubscription = false
    @State private var browserDestination: InAppBrowserDestination?

    private let durations = [5, 10, 15, 20]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    greeting
                    durationPicker
                    digestCard
                    expiringSection
                    weeklySummary
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
        }
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("おかえりなさい")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Text("あとで読むを、\nいま聴けるに。")
                .font(.largeTitle.bold())

            Label("未消化の記事が\(unreadArticles.count)件あります", systemImage: "tray.full.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
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

    private var weeklySummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("今週のデトックス")
                .font(.title3.bold())

            HStack(alignment: .top, spacing: 14) {
                metricCard(value: "\(weeklyCompletedCount)", unit: "記事", label: "消化した記事", color: .green)
                metricCard(value: "\(articleLibrary.articles.count)", unit: "記事", label: "保存した記事", color: .blue)
            }
        }
    }

    private func metricCard(value: String, unit: String, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: label == "消化した記事" ? "checkmark.circle.fill" : "tray.full.fill")
                .font(.headline)
                .foregroundStyle(color)
                .frame(width: 38, height: 38)
                .background(color.opacity(0.12), in: Circle())

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.title2.bold())
                Text(unit).font(.caption.weight(.semibold))
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 126, alignment: .leading)
        .detoxMetricCard(tint: color)
        .accessibilityElement(children: .combine)
    }

    private var weeklyCompletedCount: Int {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .distantPast
        return articleLibrary.articles.filter {
            $0.state == .completed && ($0.completedAt ?? $0.savedAt) >= weekAgo
        }.count
    }
}

#Preview {
    HomeView(articleLibrary: ArticleLibrary(), subscriptionStore: SubscriptionStore())
}
