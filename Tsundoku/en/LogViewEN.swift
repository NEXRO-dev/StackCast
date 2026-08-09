//
//  LogViewEN.swift
//  Tsundoku
//

import Charts
import SwiftUI

struct LogViewEN: View {
    @Environment(\.openURL) private var openURL
    let articleLibrary: ArticleLibrary

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
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Log").font(.largeTitle.bold())
            Text("Your actual progress across saved articles.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var metrics: some View {
        HStack(spacing: 12) {
            logMetric(value: "\(weeklyCompletedCount)", unit: "articles", label: "This week", symbol: "checkmark.circle.fill", color: .green)
            logMetric(value: "\(completedArticles.count)", unit: "articles", label: "All time", symbol: "books.vertical.fill", color: .blue)
        }
    }

    private func logMetric(value: String, unit: String, label: String, symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol).font(.title3).foregroundStyle(color)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.title.bold())
                Text(unit).font(.caption.weight(.semibold))
            }
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 105, alignment: .leading)
        .tsundokuCard()
    }

    private var activityChart: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Completed in the Last 7 Days").font(.headline)
                Spacer()
                Text("\(weeklyCompletedCount) total")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Chart(weeklyData) { item in
                BarMark(
                    x: .value("Day", item.date, unit: .day),
                    y: .value("Articles", item.count)
                )
                .foregroundStyle(.indigo.gradient)
                .cornerRadius(6)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
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
                Image(systemName: "tray.full.fill").foregroundStyle(.orange)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text("CURRENTLY UNREAD").font(.caption).foregroundStyle(.secondary)
                Text("\(unreadCount) articles left").font(.headline)
            }
            Spacer()
        }
        .tsundokuCard()
    }

    @ViewBuilder
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Recently Completed").font(.title3.bold())

            if completedArticles.isEmpty {
                ContentUnavailableView(
                    "No Completed Articles",
                    systemImage: "checkmark.circle",
                    description: Text("Articles marked as completed will be recorded here.")
                )
                .frame(maxWidth: .infinity)
                .tsundokuCard()
            } else {
                VStack(spacing: 18) {
                    ForEach(Array(completedArticles.prefix(5).enumerated()), id: \.element.id) { index, article in
                        Button { openURL(article.url) } label: {
                            ArticleRow(article: article.displayArticle(language: .english), showsStatus: false, language: .english)
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
            .map { $0.displayArticle(language: .english) }
            .filter { $0.status == .unread || $0.status == .inProgress }
            .count
    }

    private var weeklyCompletedCount: Int {
        weeklyData.reduce(0) { $0 + $1.count }
    }

    private var weeklyData: [DayCompletionEN] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        return (0..<7).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let nextDate = calendar.date(byAdding: .day, value: 1, to: date) ?? date
            let count = completedArticles.filter {
                let completedAt = $0.completedAt ?? $0.savedAt
                return completedAt >= date && completedAt < nextDate
            }.count
            return DayCompletionEN(date: date, count: count)
        }
    }
}

private struct DayCompletionEN: Identifiable {
    var id: Date { date }
    let date: Date
    let count: Int
}

#Preview {
    LogViewEN(articleLibrary: ArticleLibrary())
}
