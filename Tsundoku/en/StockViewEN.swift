//
//  StockViewEN.swift
//  Tsundoku
//

import SwiftUI

struct StockViewEN: View {
    @Environment(\.openURL) private var openURL
    let articleLibrary: ArticleLibrary
    @State private var selectedStatus: ArticleStatus = .unread
    @State private var isAddingURL = false

    private var filteredArticles: [MockArticle] {
        articleLibrary.articles
            .map { $0.displayArticle(language: .english) }
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
                                ArticleRow(article: article, language: .english)
                                    .tsundokuCard()
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                if let url = article.originalURL {
                                    Button("Open Original", systemImage: "safari") {
                                        openURL(url)
                                    }
                                }
                                Button("Mark as Completed", systemImage: "checkmark.circle") {
                                    articleLibrary.mark(article.id, as: .completed)
                                }
                                Button("Delete", systemImage: "trash", role: .destructive) {
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
                            "No Articles",
                            systemImage: selectedStatus == .completed ? "checkmark.circle" : "tray",
                            description: Text("There are no articles with this status yet.")
                        )
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Spacer()

                    GlassAddButton(accessibilityLabel: "Add Article from URL") {
                        isAddingURL = true
                    }
                }
                .padding(.horizontal, AppDesign.pagePadding)
                .padding(.bottom, 61)
            }
            .sheet(isPresented: $isAddingURL) {
                AddArticleSheetEN(articleLibrary: articleLibrary)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Saved Articles")
                    .font(.largeTitle.bold())
                Text("Read it, hear it, or let it go within 5 days.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(unreadCount)")
                .font(.title2.bold())
                .foregroundStyle(.tint)
                .padding(12)
                .background(.tint.opacity(0.12), in: Circle())
                .accessibilityLabel("\(unreadCount) unread articles")
        }
        .padding(.horizontal, AppDesign.pagePadding)
        .padding(.top, 18)
        .padding(.bottom, 16)
    }

    private var unreadCount: Int {
        articleLibrary.articles
            .map { $0.displayArticle(language: .english) }
            .filter { $0.status == .unread }
            .count
    }

    private var statusPicker: some View {
        Picker("Article Status", selection: $selectedStatus) {
            ForEach(ArticleStatus.allCases, id: \.self) { status in
                Text(filterTitle(for: status)).tag(status)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, AppDesign.pagePadding)
        .padding(.bottom, 8)
    }

    private func filterTitle(for status: ArticleStatus) -> String {
        switch status {
        case .unread: "Unread"
        case .inProgress: "Reading"
        case .completed: "Done"
        case .expired: "Expired"
        }
    }
}

private struct AddArticleSheetEN: View {
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
                    Text("Article URL")
                } footer: {
                    Text("We'll fetch the title and article content after saving.")
                }
            }
            .navigationTitle("Add Article")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
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
    StockViewEN(articleLibrary: ArticleLibrary())
}
