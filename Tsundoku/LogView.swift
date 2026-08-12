//
//  LogView.swift
//  Tsundoku
//

import Charts
import SwiftUI

struct LogView: View {
    let articleLibrary: ArticleLibrary
    @State private var browserDestination: InAppBrowserDestination?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    metrics
                    activityChart
                    unreadCard
                    recentSection
                }
                .padding(.horizontal, AppDesign.pagePadding)
                .padding(.top, 20)
                .padding(.bottom, 36)
            }
            .background(Color(.systemGroupedBackground))
            .sheet(item: $browserDestination) { destination in
                InAppBrowserView(url: destination.url)
                    .ignoresSafeArea()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ログ")
                .font(.largeTitle.bold())
            Text("保存した記事の実際の消化状況です。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var metrics: some View {
        HStack(spacing: 12) {
            logMetric(
                value: "\(weeklyCompletedCount)",
                unit: "記事",
                label: "今週完了",
                symbol: "checkmark.circle.fill",
                color: .green
            )
            logMetric(
                value: "\(completedArticles.count)",
                unit: "記事",
                label: "累計完了",
                symbol: "books.vertical.fill",
                color: .blue
            )
        }
    }

    private func logMetric(value: String, unit: String, label: String, symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(color)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.title.bold())
                Text(unit).font(.caption.weight(.semibold))
            }

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 105, alignment: .leading)
        .tsundokuCard()
    }

    private var activityChart: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("過去7日間の完了記事")
                    .font(.headline)
                Spacer()
                Text("合計 \(weeklyCompletedCount)記事")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Chart(weeklyData) { item in
                BarMark(
                    x: .value("日", item.date, unit: .day),
                    y: .value("記事", item.count)
                )
                .foregroundStyle(.indigo.gradient)
                .cornerRadius(6)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
            }
            .frame(height: 180)
        }
        .tsundokuCard()
    }

    private var unreadCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(.orange.opacity(0.14))
                Image(systemName: "tray.full.fill")
                    .foregroundStyle(.orange)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text("現在の未消化")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("あと\(unreadCount)記事")
                    .font(.headline)
            }

            Spacer()
        }
        .tsundokuCard()
    }

    @ViewBuilder
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("最近完了した記事")
                .font(.title3.bold())

            if completedArticles.isEmpty {
                ContentUnavailableView(
                    "完了した記事はありません",
                    systemImage: "checkmark.circle",
                    description: Text("ストックで記事を完了にすると、ここに記録されます。")
                )
                .frame(maxWidth: .infinity)
                .tsundokuCard()
            } else {
                VStack(spacing: 18) {
                    ForEach(Array(completedArticles.prefix(5).enumerated()), id: \.element.id) { index, article in
                        Button {
                            browserDestination = InAppBrowserDestination(url: article.url)
                        } label: {
                            ArticleRow(article: article.displayArticle(language: .japanese), showsStatus: false)
                        }
                        .buttonStyle(.plain)

                        if index < min(completedArticles.count, 5) - 1 {
                            Divider().padding(.leading, 78)
                        }
                    }
                }
                .tsundokuCard()
            }
        }
    }

    private var completedArticles: [SavedArticle] {
        articleLibrary.articles
            .filter { $0.state == .completed }
            .sorted { ($0.completedAt ?? $0.savedAt) > ($1.completedAt ?? $1.savedAt) }
    }

    private var unreadCount: Int {
        articleLibrary.articles
            .map { $0.displayArticle(language: .japanese) }
            .filter { $0.status == .unread || $0.status == .inProgress }
            .count
    }

    private var weeklyCompletedCount: Int {
        weeklyData.reduce(0) { $0 + $1.count }
    }

    private var weeklyData: [DayCompletion] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        return (0..<7).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let nextDate = calendar.date(byAdding: .day, value: 1, to: date) ?? date
            let count = completedArticles.filter {
                let completedAt = $0.completedAt ?? $0.savedAt
                return completedAt >= date && completedAt < nextDate
            }.count
            return DayCompletion(date: date, count: count)
        }
    }
}

private struct DayCompletion: Identifiable {
    var id: Date { date }
    let date: Date
    let count: Int
}

#Preview {
    LogView(articleLibrary: ArticleLibrary())
}
