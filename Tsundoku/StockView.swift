//
//  StockView.swift
//  Tsundoku
//

import SwiftUI

struct StockView: View {
    @Environment(\.openURL) private var openURL
    let articleLibrary: ArticleLibrary
    @State private var selectedStatus: ArticleStatus = .unread
    @State private var isAddingURL = false

    private var filteredArticles: [MockArticle] {
        articleLibrary.articles
            .map { $0.displayArticle(language: .japanese) }
            .filter { $0.status == selectedStatus }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                statusPicker

                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredArticles) { article in
                            Button {
                                articleLibrary.mark(article.id, as: .inProgress)
                                if let url = article.originalURL { openURL(url) }
                            } label: {
                                ArticleRow(article: article)
                                    .tsundokuCard()
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                if let url = article.originalURL {
                                    Button("元記事を開く", systemImage: "safari") {
                                        openURL(url)
                                    }
                                }
                                Button("完了にする", systemImage: "checkmark.circle") {
                                    articleLibrary.mark(article.id, as: .completed)
                                }
                                Button("削除", systemImage: "trash", role: .destructive) {
                                    articleLibrary.delete(article.id)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, AppDesign.pagePadding)
                    .padding(.top, 18)
                    .padding(.bottom, 100)
                }
                .overlay {
                    if filteredArticles.isEmpty {
                        ContentUnavailableView(
                            "記事はありません",
                            systemImage: selectedStatus == .completed ? "checkmark.circle" : "tray",
                            description: Text("この状態の記事はまだありません。")
                        )
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Spacer()

                    GlassAddButton(accessibilityLabel: "URLから記事を追加") {
                        isAddingURL = true
                    }
                }
                .padding(.horizontal, AppDesign.pagePadding)
                .padding(.bottom, 61)
            }
            .sheet(isPresented: $isAddingURL) {
                AddArticleSheet(articleLibrary: articleLibrary)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("保存した記事")
                    .font(.largeTitle.bold())
                Text("5日以内に、読むか聴くか決めましょう。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(unreadCount)")
                .font(.title2.bold())
                .foregroundStyle(.tint)
                .padding(12)
                .background(.tint.opacity(0.12), in: Circle())
                .accessibilityLabel("未消化\(unreadCount)件")
        }
        .padding(.horizontal, AppDesign.pagePadding)
        .padding(.top, 18)
        .padding(.bottom, 16)
    }

    private var unreadCount: Int {
        articleLibrary.articles
            .map { $0.displayArticle(language: .japanese) }
            .filter { $0.status == .unread }
            .count
    }

    private var statusPicker: some View {
        Picker("記事の状態", selection: $selectedStatus) {
            ForEach(ArticleStatus.allCases, id: \.self) { status in
                Text(status.rawValue).tag(status)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, AppDesign.pagePadding)
        .padding(.bottom, 8)
    }
}

private struct AddArticleSheet: View {
    @Environment(\.dismiss) private var dismiss
    let articleLibrary: ArticleLibrary
    @State private var urlText = ""
    @FocusState private var isURLFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://example.com/article", text: $urlText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($isURLFocused)
                } header: {
                    Text("記事URL")
                } footer: {
                    Text("タイトルや本文は保存後に自動で取得します。")
                }
            }
            .navigationTitle("記事を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        guard let url = URL(string: urlText), articleLibrary.add(url: url) else { return }
                        dismiss()
                    }
                    .disabled(!isValidWebURL)
                }
            }
            .onAppear { isURLFocused = true }
        }
        .presentationDetents([.medium])
    }

    private var isValidWebURL: Bool {
        guard let scheme = URL(string: urlText)?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}

#Preview {
    StockView(articleLibrary: ArticleLibrary())
}
