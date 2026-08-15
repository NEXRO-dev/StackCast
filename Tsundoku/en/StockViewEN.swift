//
//  StockViewEN.swift
//  Tsundoku
//

import SwiftUI

struct StockViewEN: View {
    @Environment(\.openURL) private var openURL
    let articleLibrary: ArticleLibrary
    let subscriptionStore: SubscriptionStore
    let castStore: CastStore
    let authStore: AuthStore
    @State private var selectedFilter: StockFilter = .all
    @State private var selectedArticleIDs: Set<UUID> = []
    @State private var isShowingCastCreated = false
    @State private var isShowingCastError = false
    @State private var browserDestination: InAppBrowserDestination?
    @State private var isAddingURL = false
    @State private var isShowingAIConsent = false
    @AppStorage("aiArticleProcessingConsentAccepted") private var aiProcessingConsentAccepted = false

    private var filteredArticles: [MockArticle] {
        let articles: [SavedArticle]
        switch selectedFilter {
        case .all:
            articles = articleLibrary.articles
        case .expiring:
            articles = articleLibrary.articles.filter(isExpiring)
        case .completed:
            articles = articleLibrary.articles.filter { $0.state == .completed }
        }

        return articles.map { $0.displayArticle(language: .english) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                statusPicker

                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredArticles) { article in
                            HStack(spacing: 8) {
                                selectionControl(for: article)

                                Button {
                                    if let url = article.originalURL {
                                        articleLibrary.mark(article.id, as: .inProgress)
                                        browserDestination = InAppBrowserDestination(url: url)
                                    }
                                } label: {
                                    ArticleRow(article: article, language: .english)
                                        .tsundokuCard()
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    if let url = article.originalURL {
                                        Button("Open Original", systemImage: "safari") {
                                            browserDestination = InAppBrowserDestination(url: url)
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
                    }
                    .padding(.horizontal, AppDesign.pagePadding)
                    .padding(.top, 18)
                    .padding(.bottom, 100)
                }
                .overlay {
                    if filteredArticles.isEmpty {
                        ContentUnavailableView(
                            "No Articles",
                            systemImage: emptyStateSymbol,
                            description: Text(emptyStateDescription)
                        )
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) {
                Group {
                    if selectedArticleIDs.isEmpty {
                        HStack {
                            Spacer()
                            GlassAddButton(accessibilityLabel: "Add Article from URL") {
                                isAddingURL = true
                            }
                        }
                    } else {
                        selectionActionBar
                    }
                }
                .padding(.horizontal, AppDesign.pagePadding)
                .padding(.bottom, 61)
                .animation(.snappy, value: selectedArticleIDs.count)
            }
            .alert("Cast created", isPresented: $isShowingCastCreated) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("You can play it from the Podcast screen.")
            }
            .confirmationDialog(
                "Cast generation failed",
                isPresented: $isShowingCastError,
                titleVisibility: .visible
            ) {
                if canRetryCast {
                    Button("Retry") {
                        createCast()
                    }
                }
                Button("Delete selected articles", role: .destructive) {
                    deleteSelectedArticles()
                }
                Button("Contact support") {
                    contactSupport()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(AppErrorMessage.cast(language: .english, code: castStore.errorCode))
            }
            .sheet(isPresented: $isAddingURL) {
                AddArticleSheetEN(articleLibrary: articleLibrary, subscriptionStore: subscriptionStore)
            }
            .sheet(isPresented: $isShowingAIConsent) {
                AIDataConsentSheet(language: .english)
            }
            .sheet(item: $browserDestination) { destination in
                InAppBrowserView(url: destination.url)
                    .ignoresSafeArea()
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
        Picker("Stock filter", selection: $selectedFilter) {
            Text("All").tag(StockFilter.all)
            Text("Expiring").tag(StockFilter.expiring)
            Text("Done").tag(StockFilter.completed)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, AppDesign.pagePadding)
        .padding(.bottom, 8)
    }

    private var emptyStateSymbol: String {
        switch selectedFilter {
        case .all, .expiring: "tray"
        case .completed: "checkmark.circle"
        }
    }

    private var emptyStateDescription: String {
        switch selectedFilter {
        case .all: "Add articles from the Share menu."
        case .expiring: "No articles expire within 24 hours."
        case .completed: "No completed articles yet."
        }
    }

    private func isExpiring(_ article: SavedArticle) -> Bool {
        guard article.state != .completed,
              let retentionInterval = SharedArticleRepository.subscriptionTier.retentionInterval
        else { return false }

        let expirationDate = article.savedAt.addingTimeInterval(retentionInterval)
        return expirationDate <= Date.now.addingTimeInterval(24 * 60 * 60)
    }

    private var selectionActionBar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Articles for Cast")
                        .font(.headline)
                    Text(selectionStatusText)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Button {
                    withAnimation(.snappy) {
                        selectedArticleIDs.removeAll()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .frame(width: 30, height: 30)
                        .background(.secondary.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear all selections")
            }

            Button {
                guard aiProcessingConsentAccepted else {
                    isShowingAIConsent = true
                    return
                }
                createCast()
            } label: {
                HStack {
                    if castStore.isGenerating {
                        ProgressView()
                            .tint(.white)
                        Text("Creating Cast…")
                    } else {
                        Text("Create Cast")
                    }
                    Spacer()
                    Image(systemName: castStore.isGenerating ? "waveform" : "arrow.right")
                }
                .font(.headline.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedArticleIDs.count < minimumCastArticleCount || castStore.isGenerating)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
    }

    private func createCast() {
        let sources = articleLibrary.articles.filter { selectedArticleIDs.contains($0.id) }
        Task {
            let cast = await castStore.create(
                token: authStore.sessionToken(),
                durationMinutes: castTestDuration,
                sources: sources
            )
            if cast != nil {
                sources.forEach { articleLibrary.mark($0.id, as: .completed) }
                selectedArticleIDs.removeAll()
                isShowingCastCreated = true
            } else {
                isShowingCastError = true
            }
        }
    }

    private var canRetryCast: Bool {
        switch castStore.errorCode {
        case "content_not_allowed", "insufficient_credits", "invalid_sources":
            return false
        default:
            return true
        }
    }

    private func deleteSelectedArticles() {
        selectedArticleIDs.forEach { articleLibrary.delete($0) }
        selectedArticleIDs.removeAll()
    }

    private func contactSupport() {
        guard let url = URL(string: "mailto:support@stackcast.app?subject=StackCast%20Cast%20generation%20support") else { return }
        openURL(url)
    }

    private var selectionStatusText: String {
        if selectedArticleIDs.count < minimumCastArticleCount {
            return "Select \(minimumCastArticleCount - selectedArticleIDs.count) more"
        }
        return "\(selectedArticleIDs.count) selected · Ready to create a Cast"
    }

    private var minimumCastArticleCount: Int {
        #if DEBUG
        return 1
        #else
        return 3
        #endif
    }

    private var castTestDuration: Int {
        #if DEBUG
        return 2
        #else
        return 10
        #endif
    }

    private func toggleSelection(for articleID: UUID) {
        guard articleLibrary.articles.first(where: { $0.id == articleID })?.state != .completed else { return }

        if selectedArticleIDs.contains(articleID) {
            selectedArticleIDs.remove(articleID)
        } else {
            selectedArticleIDs.insert(articleID)
        }
    }

    private func selectionControl(for article: MockArticle) -> some View {
        Button {
            toggleSelection(for: article.id)
        } label: {
            Image(systemName: selectedArticleIDs.contains(article.id) ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(selectedArticleIDs.contains(article.id) ? Color.accentColor : Color.secondary)
                .frame(width: 34, height: 54)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(article.status == .completed)
        .accessibilityLabel(selectedArticleIDs.contains(article.id) ? "Deselect article" : "Select article")
    }
}

private struct AddArticleSheetEN: View {
    @Environment(\.dismiss) private var dismiss
    let articleLibrary: ArticleLibrary
    let subscriptionStore: SubscriptionStore
    @State private var urlText = ""
    @State private var isShowingSubscription = false
    @FocusState private var isURLFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Enter article URL", text: $urlText)
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
                        guard let url = URL(string: urlText) else { return }
                        switch articleLibrary.addWithResult(url: url) {
                        case .saved:
                            dismiss()
                        case .limitReached:
                            isShowingSubscription = true
                        case .invalidURL, .failed:
                            break
                        }
                    }
                    .disabled(!isValidWebURL)
                }
            }
            .onAppear { isURLFocused = true }
        }
        .presentationDetents([.medium])
        .sheet(isPresented: $isShowingSubscription) {
            SubscriptionManagementView(
                subscriptionStore: subscriptionStore,
                language: .english,
                initialTier: .plus
            )
        }
    }

    private var isValidWebURL: Bool {
        guard let scheme = URL(string: urlText)?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}

#Preview {
    StockViewEN(
        articleLibrary: ArticleLibrary(),
        subscriptionStore: SubscriptionStore(),
        castStore: CastStore(),
        authStore: AuthStore()
    )
}
