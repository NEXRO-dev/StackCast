//
//  HomeViewEN.swift
//  Tsundoku
//

import SwiftUI

struct HomeViewEN: View {
    @Environment(\.openURL) private var openURL
    let articleLibrary: ArticleLibrary
    @AppStorage("customDigestDuration") private var customDuration = 20
    @State private var selectedDuration = 10
    @State private var durationSelection = 10
    @State private var isShowingCustomDuration = false

    private let durations = [5, 10, 15, 30]

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
                CustomDurationSheet(language: .english, initialDuration: customDuration) { duration in
                    customDuration = duration
                    selectedDuration = duration
                    durationSelection = -1
                }
            }
        }
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Welcome back")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Text("Turn save for later\ninto listen now.")
                .font(.largeTitle.bold())

            Label("You have \(unreadArticles.count) unread articles", systemImage: "tray.full.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var durationPicker: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How much time do you have?")
                .font(.headline)

            DurationSegmentedControl(
                selection: $durationSelection,
                durations: durations,
                customDuration: customDuration,
                language: .english,
                onCustomize: { isShowingCustomDuration = true }
            )
            .onChange(of: durationSelection) { _, selection in
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

                    Text("\(selectedDuration) minutes before work")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                }

                Spacer()

                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.white)
            }

            Text("Available after the audio generation backend is connected")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))

            Button {} label: {
                Label("Digest Generation Coming Soon", systemImage: "waveform.badge.exclamationmark")
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
                Text("Expiring Soon")
                    .font(.title3.bold())
                Spacer()
                Button("See All") {}
                    .font(.caption.weight(.semibold))
            }

            if unreadArticles.isEmpty {
                ContentUnavailableView(
                    "No Saved Articles",
                    systemImage: "tray",
                    description: Text("Share a web page to add it here.")
                )
                .frame(maxWidth: .infinity)
                .tsundokuCard()
            } else {
                VStack(spacing: 18) {
                    ForEach(Array(unreadArticles.prefix(2).enumerated()), id: \.element.id) { index, article in
                        Button {
                            articleLibrary.mark(article.id, as: .inProgress)
                            if let url = article.originalURL { openURL(url) }
                        } label: {
                            ArticleRow(article: article, language: .english)
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
            .map { $0.displayArticle(language: .english) }
            .filter { $0.status == .unread }
    }

    private var weeklySummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("This Week's Detox")
                .font(.title3.bold())

            HStack(alignment: .top, spacing: 14) {
                metricCard(value: "\(weeklyCompletedCount)", unit: "articles", label: "Completed", symbol: "checkmark.circle.fill", color: .green)
                metricCard(value: "\(articleLibrary.articles.count)", unit: "articles", label: "Saved", symbol: "tray.full.fill", color: .blue)
            }
        }
    }

    private func metricCard(value: String, unit: String, label: String, symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol)
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
    HomeViewEN(articleLibrary: ArticleLibrary())
}
