import Foundation
import Observation
import SwiftUI

struct RecommendationTopic: Codable, Identifiable, Hashable {
    let id: String
    let nameJA: String
    let nameEN: String

    func name(language: AppLanguage) -> String { language == .english ? nameEN : nameJA }

    static let defaults: [RecommendationTopic] = [
        .init(id: "technology", nameJA: "テクノロジー", nameEN: "Technology"),
        .init(id: "business", nameJA: "ビジネス", nameEN: "Business"),
        .init(id: "science", nameJA: "科学", nameEN: "Science"),
        .init(id: "entertainment", nameJA: "エンタメ", nameEN: "Entertainment"),
        .init(id: "sports", nameJA: "スポーツ", nameEN: "Sports"),
        .init(id: "society", nameJA: "社会", nameEN: "Society"),
        .init(id: "world", nameJA: "国際", nameEN: "World"),
        .init(id: "health", nameJA: "健康", nameEN: "Health"),
        .init(id: "culture", nameJA: "文化", nameEN: "Culture"),
    ]
}

struct RecommendedNewsItem: Codable, Identifiable, Hashable {
    struct Article: Codable, Hashable {
        let id: String
        let url: URL
        let title: String
        let description: String?
        let imageURL: URL?
        let source: String
        let publishedAt: String
    }

    let article: Article
    let topicIDs: [String]
    let reason: String
    let reasonEN: String
    let rank: Int
    var id: String { article.id }
}

struct RecommendationProfile: Codable {
    struct SelectedTopic: Codable, Identifiable {
        let id: String
        let nameJA: String
        let nameEN: String
    }

    struct CustomInterest: Codable, Identifiable, Hashable {
        let id: String
        let label: String
        let topicID: String

        init(id: String = UUID().uuidString, label: String, topicID: String) {
            self.id = id
            self.label = label
            self.topicID = topicID
        }
    }

    let ageBand: String?
    let gender: String?
    let personalizationEnabled: Int?
    let dailyAutoCastEnabled: Int?
    let dailyCastDurationMinutes: Int?
    let aiProcessingConsentAt: String?
    let topics: [SelectedTopic]
    let customInterests: [CustomInterest]?
}

struct RecommendationMemoryItem: Codable, Identifiable {
    let id: String
    let kind: String
    let value: String
    let polarity: String
    let weight: Double
    let reason: String
}

private struct InterestSuggestion: Identifiable, Hashable {
    let id: String
    let nameJA: String
    let nameEN: String
    let topicID: String
    let keywords: [String]

    func name(language: AppLanguage) -> String { language == .english ? nameEN : nameJA }

    static let catalog: [InterestSuggestion] = [
        .init(id: "generative-ai", nameJA: "生成AI", nameEN: "Generative AI", topicID: "technology", keywords: ["生成ai", "genai", "llm", "chatgpt", "claude", "gemini"]),
        .init(id: "ai-ml", nameJA: "AI・機械学習", nameEN: "AI & Machine Learning", topicID: "technology", keywords: ["ai", "人工知能", "機械学習", "deep learning"]),
        .init(id: "programming", nameJA: "プログラミング", nameEN: "Programming", topicID: "technology", keywords: ["開発", "software", "エンジニア", "コード"]),
        .init(id: "gadgets", nameJA: "ガジェット", nameEN: "Gadgets", topicID: "technology", keywords: ["iphone", "スマホ", "device", "デバイス"]),
        .init(id: "startups", nameJA: "スタートアップ", nameEN: "Startups", topicID: "business", keywords: ["起業", "startup", "ベンチャー"]),
        .init(id: "investing", nameJA: "投資・株式", nameEN: "Investing & Stocks", topicID: "business", keywords: ["投資", "株", "market", "資産運用"]),
        .init(id: "space", nameJA: "宇宙", nameEN: "Space", topicID: "science", keywords: ["宇宙", "nasa", "ロケット", "天文"]),
        .init(id: "climate", nameJA: "環境・気候", nameEN: "Climate & Environment", topicID: "science", keywords: ["環境", "気候", "脱炭素", "climate"]),
        .init(id: "movies", nameJA: "映画", nameEN: "Movies", topicID: "entertainment", keywords: ["映画", "cinema", "movie"]),
        .init(id: "music", nameJA: "音楽", nameEN: "Music", topicID: "entertainment", keywords: ["音楽", "music", "アーティスト"]),
        .init(id: "games", nameJA: "ゲーム", nameEN: "Gaming", topicID: "entertainment", keywords: ["ゲーム", "gaming", "esports"]),
        .init(id: "football", nameJA: "サッカー", nameEN: "Football", topicID: "sports", keywords: ["サッカー", "football", "soccer"]),
        .init(id: "baseball", nameJA: "野球", nameEN: "Baseball", topicID: "sports", keywords: ["野球", "baseball", "mlb"]),
        .init(id: "education", nameJA: "教育", nameEN: "Education", topicID: "society", keywords: ["教育", "学校", "learning"]),
        .init(id: "politics", nameJA: "政治", nameEN: "Politics", topicID: "society", keywords: ["政治", "選挙", "政策"]),
        .init(id: "global-affairs", nameJA: "海外情勢", nameEN: "Global Affairs", topicID: "world", keywords: ["海外", "外交", "国際情勢"]),
        .init(id: "medicine", nameJA: "医療", nameEN: "Medicine", topicID: "health", keywords: ["医療", "medicine", "病院"]),
        .init(id: "mental-health", nameJA: "メンタルヘルス", nameEN: "Mental Health", topicID: "health", keywords: ["心", "心理", "mental health"]),
        .init(id: "books", nameJA: "本・読書", nameEN: "Books & Reading", topicID: "culture", keywords: ["本", "読書", "book", "文学"]),
        .init(id: "art", nameJA: "アート", nameEN: "Art", topicID: "culture", keywords: ["美術", "芸術", "art"]),
    ]
}

private enum PersonalizationSheet: String, Identifiable {
    case addInterest
    var id: String { rawValue }
}

private struct TopicsResponse: Decodable { let topics: [RecommendationTopic] }
private struct ProfileResponse: Decodable { let profile: RecommendationProfile }
private struct MemoryResponse: Decodable { let items: [RecommendationMemoryItem] }
private struct FeedResponse: Decodable {
    struct DailyCast: Decodable { let status: String; let castId: String? }
    let feedId: String
    let editionDate: String
    let status: String
    let isFallback: Bool
    let items: [RecommendedNewsItem]
    let dailyCast: DailyCast
}

private struct RecommendationAPIErrorEnvelope: Decodable {
    struct APIError: Decodable {
        let code: String?
        let message: String?
    }
    let error: APIError
}

private struct RecommendationRequestError: LocalizedError {
    let statusCode: Int
    let serverMessage: String?

    var errorDescription: String? {
        if let serverMessage, !serverMessage.isEmpty {
            return "\(serverMessage) (HTTP \(statusCode))"
        }
        return "Request failed. (HTTP \(statusCode))"
    }
}

@MainActor
@Observable
final class RecommendationStore {
    private(set) var topics: [RecommendationTopic] = RecommendationTopic.defaults
    private(set) var profile: RecommendationProfile?
    private(set) var items: [RecommendedNewsItem] = []
    private(set) var memoryItems: [RecommendationMemoryItem] = []
    private(set) var editionDate = ""
    private(set) var feedID = ""
    private(set) var dailyCastStatus = "disabled"
    private(set) var dailyCastID: String?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let client = RecommendationClient()
    private var recordedImpressionFeedIDs: Set<String> = []

    var requiresSetup: Bool { profile != nil && (profile?.topics.count ?? 0) < 3 }

    func load(token: String?) async {
        guard let token else { return }
        isLoading = true
        errorMessage = nil
        do {
            async let loadedTopics = client.topics()
            async let loadedProfile = client.profile(token: token)
            async let loadedFeed = client.feed(token: token)
            async let loadedMemory = client.memory(token: token)
            let fetchedTopics = try await loadedTopics
            if !fetchedTopics.isEmpty {
                topics = fetchedTopics
            }
            profile = try await loadedProfile
            let feed = try await loadedFeed
            memoryItems = try await loadedMemory
            items = feed.items
            feedID = feed.feedId
            editionDate = feed.editionDate
            dailyCastStatus = feed.dailyCast.status
            dailyCastID = feed.dailyCast.castId
            await recordImpressionsIfNeeded(token: token)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func saveProfile(
        token: String?,
        ageBand: String,
        gender: String,
        topicIDs: Set<String>,
        customInterests: [RecommendationProfile.CustomInterest],
        personalizationEnabled: Bool,
        dailyAutoCastEnabled: Bool,
        durationMinutes: Int,
        aiConsent: Bool
    ) async throws {
        guard let token else { throw URLError(.userAuthenticationRequired) }
        profile = try await client.saveProfile(
            token: token,
            ageBand: ageBand,
            gender: gender,
            topicIDs: Array(topicIDs),
            customInterests: customInterests,
            personalizationEnabled: personalizationEnabled,
            dailyAutoCastEnabled: dailyAutoCastEnabled,
            durationMinutes: durationMinutes,
            aiConsent: aiConsent
        )
        do {
            let feed = try await client.feed(token: token)
            items = feed.items
            feedID = feed.feedId
            editionDate = feed.editionDate
            dailyCastStatus = feed.dailyCast.status
            dailyCastID = feed.dailyCast.castId
            await recordImpressionsIfNeeded(token: token)
        } catch {
            // Profile persistence already succeeded. Refreshing today's feed can retry later.
            errorMessage = "Saved preferences, but today's news could not be refreshed yet."
        }
    }

    func record(token: String?, articleID: String, event: String, position: Int? = nil) async {
        guard let token else { return }
        try? await client.record(token: token, articleID: articleID, event: event, position: position)
        if event == "dislike" {
            withAnimation(.snappy) { items.removeAll { $0.id == articleID } }
        }
    }

    private func recordImpressionsIfNeeded(token: String) async {
        guard !feedID.isEmpty, !recordedImpressionFeedIDs.contains(feedID), !items.isEmpty else { return }
        recordedImpressionFeedIDs.insert(feedID)
        try? await client.recordBatch(
            token: token,
            items: items.map { ($0.id, "impression", $0.rank, nil) }
        )
    }

    func deleteMemory(token: String?, id: String) async {
        guard let token else { return }
        do {
            try await client.deleteMemory(token: token, id: id)
            memoryItems.removeAll { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resetMemory(token: String?) async {
        guard let token else { return }
        do {
            try await client.resetMemory(token: token)
            memoryItems = []
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct RecommendationClient {
    private let baseURL = Config.apiBaseURL

    func topics() async throws -> [RecommendationTopic] {
        let response: TopicsResponse = try await send(path: "recommendations/topics")
        return response.topics
    }

    func profile(token: String) async throws -> RecommendationProfile {
        let response: ProfileResponse = try await send(path: "recommendations/profile", token: token)
        return response.profile
    }

    func feed(token: String) async throws -> FeedResponse {
        try await send(path: "recommendations/feed", token: token)
    }

    func memory(token: String) async throws -> [RecommendationMemoryItem] {
        let response: MemoryResponse = try await send(path: "recommendations/memory", token: token)
        return response.items
    }

    func saveProfile(
        token: String,
        ageBand: String,
        gender: String,
        topicIDs: [String],
        customInterests: [RecommendationProfile.CustomInterest],
        personalizationEnabled: Bool,
        dailyAutoCastEnabled: Bool,
        durationMinutes: Int,
        aiConsent: Bool
    ) async throws -> RecommendationProfile {
        let response: ProfileResponse = try await send(
            path: "recommendations/profile",
            method: "PUT",
            json: [
                "ageBand": ageBand,
                "gender": gender == "unspecified" ? NSNull() : gender,
                "topicIDs": topicIDs,
                "customInterests": customInterests.map { ["label": $0.label, "topicID": $0.topicID] },
                "personalizationEnabled": personalizationEnabled,
                "dailyAutoCastEnabled": dailyAutoCastEnabled,
                "dailyCastDurationMinutes": durationMinutes,
                "aiProcessingConsent": aiConsent,
            ],
            token: token
        )
        return response.profile
    }

    func record(token: String, articleID: String, event: String, position: Int?) async throws {
        try await recordBatch(token: token, items: [(articleID, event, position, nil)])
    }

    func recordBatch(token: String, items: [(String, String, Int?, Int?)]) async throws {
        let formatter = ISO8601DateFormatter()
        let entries: [[String: Any]] = items.map { articleID, event, position, dwellMS in
            var entry: [String: Any] = [
                "id": UUID().uuidString,
                "articleID": articleID,
                "eventType": event,
                "surface": "home",
                "occurredAt": formatter.string(from: .now),
            ]
            if let position { entry["position"] = position }
            if let dwellMS { entry["dwellMS"] = dwellMS }
            return entry
        }
        let _: EmptyAPIResponse = try await send(
            path: "recommendations/events", method: "POST", json: ["events": entries], token: token
        )
    }

    func deleteMemory(token: String, id: String) async throws {
        let _: EmptyAPIResponse = try await send(path: "recommendations/memory/\(id)", method: "DELETE", token: token)
    }

    func resetMemory(token: String) async throws {
        let _: EmptyAPIResponse = try await send(path: "recommendations/memory", method: "DELETE", token: token)
    }

    private func send<Response: Decodable>(
        path: String,
        method: String = "GET",
        json: [String: Any]? = nil,
        token: String? = nil
    ) async throws -> Response {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let json {
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            let envelope = try? JSONDecoder().decode(RecommendationAPIErrorEnvelope.self, from: data)
            throw RecommendationRequestError(
                statusCode: http.statusCode,
                serverMessage: envelope?.error.message
            )
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}

private struct EmptyAPIResponse: Decodable {
    init(from decoder: Decoder) throws {}
}

struct PersonalNewsHomeView: View {
    let authStore: AuthStore
    let articleLibrary: ArticleLibrary
    let subscriptionStore: SubscriptionStore
    let language: AppLanguage
    let store: RecommendationStore

    @State private var browserDestination: InAppBrowserDestination?
    @State private var showsSetup = false
    @State private var openedArticleID: String?
    @State private var openedArticleRank: Int?
    @State private var openedAt: Date?

    private var isEnglish: Bool { language == .english }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            header
            dailyCastBanner
            feedContent
        }
        .task {
            await store.load(token: authStore.sessionToken())
            showsSetup = store.requiresSetup
        }
        .onChange(of: store.requiresSetup) { _, required in showsSetup = required }
        .sheet(item: $browserDestination, onDismiss: recordDwell) { destination in
            InAppBrowserView(url: destination.url).ignoresSafeArea()
        }
        .sheet(isPresented: $showsSetup) {
            NavigationStack {
                PersonalizationSettingsView(
                    authStore: authStore,
                    subscriptionStore: subscriptionStore,
                    language: language,
                    store: store,
                    requiresCompletion: true
                )
            }
            .interactiveDismissDisabled(store.requiresSetup)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(isEnglish ? "TODAY'S FIVE" : "今日の5件")
                .font(.caption.weight(.bold)).tracking(1.1).foregroundStyle(.indigo)
            Text(isEnglish ? "News picked for you" : "あなたに合わせたニュース")
                .font(.largeTitle.bold())
            Text(isEnglish ? "Updated daily around 1:00 AM JST" : "毎日午前1時ごろ更新")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var dailyCastBanner: some View {
        if store.dailyCastStatus != "disabled" {
            HStack(spacing: 12) {
                Image(systemName: store.dailyCastStatus == "ready" ? "waveform.circle.fill" : "clock.badge.checkmark")
                    .font(.title2).foregroundStyle(.indigo)
                VStack(alignment: .leading, spacing: 3) {
                    Text(isEnglish ? "Daily news Cast" : "デイリーニュースCast").font(.headline)
                    Text(dailyCastStatusText).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    @ViewBuilder
    private var feedContent: some View {
        if store.isLoading && store.items.isEmpty {
            ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
        } else if store.items.isEmpty {
            ContentUnavailableView(
                isEnglish ? "No news yet" : "ニュースを準備中です",
                systemImage: "newspaper",
                description: Text(isEnglish ? "Pull to refresh or update your interests." : "下に引っ張って更新するか、興味ジャンルを設定してください。")
            )
            .frame(maxWidth: .infinity).padding(.top, 50)
        } else {
            ForEach(store.items) { item in newsCard(item) }
        }
    }

    private func newsCard(_ item: RecommendedNewsItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                openedArticleID = item.id
                openedArticleRank = item.rank
                openedAt = .now
                browserDestination = InAppBrowserDestination(url: item.article.url)
                Task { await store.record(token: authStore.sessionToken(), articleID: item.id, event: "open", position: item.rank) }
            } label: {
                VStack(alignment: .leading, spacing: 11) {
                    AsyncImage(url: item.article.imageURL) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() }
                        else { Rectangle().fill(.indigo.opacity(0.1)).overlay { Image(systemName: "newspaper.fill").foregroundStyle(.indigo) } }
                    }
                    .frame(height: 150).frame(maxWidth: .infinity).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    Text(item.article.title).font(.headline).foregroundStyle(.primary).multilineTextAlignment(.leading)
                    Text("\(item.article.source) · \(isEnglish ? item.reasonEN : item.reason)")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                }
            }
            .buttonStyle(.plain)

            HStack {
                Button {
                    _ = articleLibrary.addWithResult(url: item.article.url, title: item.article.title)
                    Task { await store.record(token: authStore.sessionToken(), articleID: item.id, event: "save", position: item.rank) }
                } label: { Label(isEnglish ? "Save" : "保存", systemImage: "tray.and.arrow.down") }
                Spacer()
                Button(role: .destructive) {
                    Task { await store.record(token: authStore.sessionToken(), articleID: item.id, event: "dislike", position: item.rank) }
                } label: { Label(isEnglish ? "Less like this" : "興味なし", systemImage: "hand.thumbsdown") }
            }
            .font(.caption.weight(.semibold)).buttonStyle(.plain)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var dailyCastStatusText: String {
        switch store.dailyCastStatus {
        case "ready": isEnglish ? "Ready to play in Podcasts" : "ポッドキャスト画面で再生できます"
        case "processing": isEnglish ? "Creating your Cast" : "Castを作成しています"
        case "queued": isEnglish ? "Waiting to be generated" : "生成待ちです"
        case "failed": isEnglish ? "News is available; audio will retry later" : "ニュースは閲覧できます。音声は後で再試行します"
        default: isEnglish ? "Not generated today" : "今日は生成されません"
        }
    }

    private func recordDwell() {
        guard let articleID = openedArticleID, let openedAt else { return }
        let dwellMS = max(0, Int(Date.now.timeIntervalSince(openedAt) * 1_000))
        let rank = openedArticleRank
        openedArticleID = nil
        openedArticleRank = nil
        self.openedAt = nil
        guard dwellMS >= 1_000, let token = authStore.sessionToken() else { return }
        Task {
            try? await RecommendationClient().recordBatch(
                token: token,
                items: [(articleID, "dwell", rank, dwellMS)]
            )
        }
    }
}

struct PersonalNewsFeedScreen: View {
    let authStore: AuthStore
    let articleLibrary: ArticleLibrary
    let subscriptionStore: SubscriptionStore
    let language: AppLanguage
    let store: RecommendationStore

    private var isEnglish: Bool { language == .english }

    var body: some View {
        ScrollView {
            PersonalNewsHomeView(
                authStore: authStore,
                articleLibrary: articleLibrary,
                subscriptionStore: subscriptionStore,
                language: language,
                store: store
            )
            .padding(.horizontal, AppDesign.pagePadding)
            .padding(.top, 18)
            .padding(.bottom, 36)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(isEnglish ? "For You" : "あなた向けニュース")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await store.load(token: authStore.sessionToken())
        }
    }
}

struct PersonalNewsHomePreview: View {
    let authStore: AuthStore
    let language: AppLanguage
    let store: RecommendationStore

    @State private var browserDestination: InAppBrowserDestination?

    private var isEnglish: Bool { language == .english }

    var body: some View {
        Group {
            if store.isLoading && store.items.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 24)
            } else if store.items.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "newspaper")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text(isEnglish ? "Today's news is being prepared." : "今日のニュースを準備中です")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(16)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(store.items.prefix(5).enumerated()), id: \.element.id) { index, item in
                        Button {
                            browserDestination = InAppBrowserDestination(url: item.article.url)
                            Task {
                                await store.record(
                                    token: authStore.sessionToken(),
                                    articleID: item.id,
                                    event: "open",
                                    position: item.rank
                                )
                            }
                        } label: {
                            HStack(spacing: 12) {
                                AsyncImage(url: item.article.imageURL) { phase in
                                    if let image = phase.image {
                                        image.resizable().scaledToFill()
                                    } else {
                                        Color.indigo.opacity(0.1)
                                            .overlay {
                                                Text("\(index + 1)")
                                                    .font(.headline.bold())
                                                    .foregroundStyle(.indigo)
                                            }
                                    }
                                }
                                .frame(width: 54, height: 54)
                                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.article.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    Text(item.article.source)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 0)

                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 15)
                            .padding(.vertical, 11)
                        }
                        .buttonStyle(.plain)

                        if index < min(store.items.count, 5) - 1 {
                            Divider().padding(.leading, 81)
                        }
                    }
                }
            }
        }
        .task {
            if store.items.isEmpty {
                await store.load(token: authStore.sessionToken())
            }
        }
        .sheet(item: $browserDestination) { destination in
            InAppBrowserView(url: destination.url)
                .ignoresSafeArea()
        }
    }
}

struct PersonalizationSettingsView: View {
    let authStore: AuthStore
    let subscriptionStore: SubscriptionStore?
    let language: AppLanguage
    let store: RecommendationStore
    var requiresCompletion = false

    @Environment(\.dismiss) private var dismiss
    @AppStorage("aiArticleProcessingConsentAccepted") private var aiConsent = false
    @State private var selectedTopics: Set<String> = []
    @State private var customInterests: [RecommendationProfile.CustomInterest] = []
    @State private var presentedSheet: PersonalizationSheet?
    @State private var ageBand = "unspecified"
    @State private var gender = "unspecified"
    @State private var personalizationEnabled = true
    @State private var autoCastEnabled = false
    @State private var durationMinutes = 5
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var isEnglish: Bool { language == .english }
    private let ageBands = ["unspecified", "under_18", "18_24", "25_34", "35_44", "45_54", "55_plus"]
    private let topicColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]
    private var selectedInterestCount: Int { selectedTopics.count + customInterests.count }

    var body: some View {
        Form {
                Section {
                    LazyVGrid(columns: topicColumns, spacing: 10) {
                        ForEach(store.topics) { topic in
                            Button {
                                withAnimation(.snappy(duration: 0.2)) {
                                    if selectedTopics.contains(topic.id) { selectedTopics.remove(topic.id) }
                                    else { selectedTopics.insert(topic.id) }
                                }
                            } label: {
                                HStack(spacing: 7) {
                                    Image(systemName: selectedTopics.contains(topic.id) ? "checkmark.circle.fill" : "circle")
                                    Text(topic.name(language: language))
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(selectedTopics.contains(topic.id) ? Color.white : Color.primary)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .padding(.horizontal, 12)
                                .background(
                                    selectedTopics.contains(topic.id) ? Color.indigo : Color.secondary.opacity(0.1),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selectedTopics.contains(topic.id) ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)

                    if !customInterests.isEmpty {
                        Divider()
                        Text(isEnglish ? "Added by you" : "追加したジャンル")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        LazyVGrid(columns: topicColumns, spacing: 10) {
                            ForEach(customInterests) { interest in
                                Button {
                                    withAnimation(.snappy) {
                                        customInterests.removeAll { $0.id == interest.id }
                                    }
                                } label: {
                                    HStack(spacing: 7) {
                                        Image(systemName: "sparkles")
                                        Text(interest.label).lineLimit(1)
                                        Spacer(minLength: 0)
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.white.opacity(0.75))
                                    }
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .padding(.horizontal, 12)
                                    .background(Color.indigo, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(isEnglish ? "Remove \(interest.label)" : "\(interest.label)を削除")
                            }
                        }
                    }

                    HStack {
                        Text(isEnglish ? "Selected" : "選択中")
                        Spacer()
                        Text("\(selectedInterestCount) / 3+")
                            .fontWeight(.semibold)
                            .foregroundStyle(selectedInterestCount >= 3 ? Color.green : Color.orange)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } header: {
                    HStack {
                        Text(isEnglish ? "Interests (choose at least 3)" : "興味ジャンル（3つ以上）")
                        Spacer()
                        Button {
                            presentedSheet = .addInterest
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.indigo)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isEnglish ? "Add an interest" : "興味ジャンルを追加")
                    }
                }
                Section(isEnglish ? "Profile" : "プロフィール") {
                    Picker(isEnglish ? "Age range" : "年代", selection: $ageBand) {
                        ForEach(ageBands, id: \.self) { Text(ageLabel($0)).tag($0) }
                    }
                    Picker(isEnglish ? "Gender (optional)" : "性別（任意）", selection: $gender) {
                        Text(isEnglish ? "Prefer not to say" : "回答しない").tag("unspecified")
                        Text(isEnglish ? "Woman" : "女性").tag("female")
                        Text(isEnglish ? "Man" : "男性").tag("male")
                        Text(isEnglish ? "Non-binary / other" : "ノンバイナリー／その他").tag("non_binary")
                    }
                    Toggle(isEnglish ? "Personalized recommendations" : "おすすめをパーソナライズ", isOn: $personalizationEnabled)
                }
                Section(isEnglish ? "Daily Cast" : "デイリーCast") {
                    Toggle(isEnglish ? "Create automatically" : "毎日自動生成", isOn: $autoCastEnabled)
                        .disabled(subscriptionStore?.isPro == false)
                    if autoCastEnabled {
                        Picker(isEnglish ? "Length" : "長さ", selection: $durationMinutes) {
                            ForEach([5, 10, 15, 20], id: \.self) { Text("\($0) min").tag($0) }
                        }
                        Toggle(isEnglish ? "I agree to AI data processing" : "AIデータ処理に同意する", isOn: $aiConsent)
                    }
                }
                if !store.memoryItems.isEmpty {
                    Section(isEnglish ? "Recommendation memory" : "おすすめメモリ") {
                        ForEach(store.memoryItems) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.value).font(.subheadline.weight(.semibold))
                                    Text(item.reason).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    Task { await store.deleteMemory(token: authStore.sessionToken(), id: item.id) }
                                } label: { Image(systemName: "trash") }
                            }
                        }
                        Button(role: .destructive) {
                            Task { await store.resetMemory(token: authStore.sessionToken()) }
                        } label: { Text(isEnglish ? "Reset learned memory" : "学習したメモリをリセット") }
                    }
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            .navigationTitle(isEnglish ? "Personalization" : "おすすめ設定")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(requiresCompletion)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text(isEnglish ? "Save" : "保存")
                                .fontWeight(.semibold)
                        }
                    }
                        .disabled(selectedInterestCount < 3 || isSaving || (autoCastEnabled && !aiConsent))
                }
            }
            .task {
                await store.load(token: authStore.sessionToken())
                selectedTopics = Set(store.profile?.topics.map(\.id) ?? [])
                customInterests = store.profile?.customInterests ?? []
                ageBand = store.profile?.ageBand ?? "unspecified"
                gender = store.profile?.gender ?? "unspecified"
                personalizationEnabled = store.profile?.personalizationEnabled != 0
                autoCastEnabled = store.profile?.dailyAutoCastEnabled == 1
                durationMinutes = store.profile?.dailyCastDurationMinutes ?? 5
                aiConsent = aiConsent || store.profile?.aiProcessingConsentAt != nil
            }
            .sheet(item: $presentedSheet) { _ in
                AddCustomInterestSheet(
                    language: language,
                    topics: store.topics,
                    customInterests: $customInterests
                )
                .presentationDetents([.medium, .large])
            }
            .alert(
                isEnglish ? "Could Not Save" : "保存できませんでした",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await store.saveProfile(
                token: authStore.sessionToken(), ageBand: ageBand, gender: gender, topicIDs: selectedTopics,
                customInterests: customInterests,
                personalizationEnabled: personalizationEnabled, dailyAutoCastEnabled: autoCastEnabled,
                durationMinutes: durationMinutes, aiConsent: aiConsent
            )
            dismiss()
        } catch {
            errorMessage = isEnglish
                ? "Your settings could not be saved. \(error.localizedDescription)"
                : "設定を保存できませんでした。\(error.localizedDescription)"
        }
    }

    private func ageLabel(_ value: String) -> String {
        switch value {
        case "under_18": isEnglish ? "Under 18" : "18歳未満"
        case "18_24": "18–24"
        case "25_34": "25–34"
        case "35_44": "35–44"
        case "45_54": "45–54"
        case "55_plus": isEnglish ? "55+" : "55歳以上"
        default: isEnglish ? "Prefer not to say" : "回答しない"
        }
    }
}

private struct AddCustomInterestSheet: View {
    let language: AppLanguage
    let topics: [RecommendationTopic]
    @Binding var customInterests: [RecommendationProfile.CustomInterest]

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selectedTopicID = "technology"

    private var isEnglish: Bool { language == .english }
    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var normalizedExistingLabels: Set<String> {
        Set(customInterests.map { normalize($0.label) })
    }
    private var matchingSuggestions: [InterestSuggestion] {
        let normalizedQuery = normalize(trimmedQuery)
        guard !normalizedQuery.isEmpty else { return Array(InterestSuggestion.catalog.prefix(8)) }
        return InterestSuggestion.catalog
            .compactMap { suggestion -> (InterestSuggestion, Int)? in
                let values = [suggestion.nameJA, suggestion.nameEN] + suggestion.keywords
                let normalizedValues = values.map(normalize)
                let score: Int
                if normalizedValues.contains(normalizedQuery) {
                    score = 100
                } else if normalizedValues.contains(where: { $0.contains(normalizedQuery) || normalizedQuery.contains($0) }) {
                    score = 70
                } else {
                    let characters = Set(normalizedQuery)
                    let overlap = normalizedValues.map { Set($0).intersection(characters).count }.max() ?? 0
                    score = overlap >= 2 ? overlap : 0
                }
                return score > 0 ? (suggestion, score) : nil
            }
            .sorted { $0.1 > $1.1 }
            .prefix(6)
            .map(\.0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(isEnglish ? "e.g. Generative AI" : "例：生成AI", text: $query)
                        .textInputAutocapitalization(.never)
                        .submitLabel(.search)
                } header: {
                    Text(isEnglish ? "What are you interested in?" : "興味のあることを入力")
                } footer: {
                    Text(isEnglish ? "We rank articles using this wording and related terms." : "入力した言葉と関連語を使い、近いニュースを優先します。")
                }

                if !matchingSuggestions.isEmpty {
                    Section(isEnglish ? "Closest suggestions" : "近い候補") {
                        ForEach(matchingSuggestions) { suggestion in
                            Button {
                                add(label: suggestion.name(language: language), topicID: suggestion.topicID)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: suggestion.id == "generative-ai" ? "sparkles" : "scope")
                                        .foregroundStyle(.indigo)
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(suggestion.name(language: language)).foregroundStyle(.primary)
                                        Text(parentTopicName(suggestion.topicID))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle.fill").foregroundStyle(.indigo)
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(normalizedExistingLabels.contains(normalize(suggestion.name(language: language))))
                        }
                    }
                }

                if !trimmedQuery.isEmpty {
                    Section {
                        Picker(isEnglish ? "Related category" : "関連する基本ジャンル", selection: $selectedTopicID) {
                            ForEach(topics) { topic in
                                Text(topic.name(language: language)).tag(topic.id)
                            }
                        }
                        Button {
                            add(label: trimmedQuery, topicID: selectedTopicID)
                        } label: {
                            Label(
                                isEnglish ? "Add “\(trimmedQuery)”" : "「\(trimmedQuery)」を追加",
                                systemImage: "plus"
                            )
                            .fontWeight(.semibold)
                        }
                        .disabled(trimmedQuery.count < 2 || normalizedExistingLabels.contains(normalize(trimmedQuery)))
                    } header: {
                        Text(isEnglish ? "Add with your wording" : "入力した名前で追加")
                    }
                }
            }
            .navigationTitle(isEnglish ? "Add Interest" : "興味ジャンルを追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isEnglish ? "Cancel" : "キャンセル") { dismiss() }
                }
            }
            .onChange(of: query) { _, _ in
                if let inferredTopicID = matchingSuggestions.first?.topicID {
                    selectedTopicID = inferredTopicID
                }
            }
        }
    }

    private func add(label: String, topicID: String) {
        let cleanLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanLabel.count >= 2, !normalizedExistingLabels.contains(normalize(cleanLabel)) else { return }
        customInterests.append(.init(label: String(cleanLabel.prefix(40)), topicID: topicID))
        dismiss()
    }

    private func parentTopicName(_ topicID: String) -> String {
        topics.first(where: { $0.id == topicID })?.name(language: language) ?? topicID
    }

    private func normalize(_ value: String) -> String {
        (value.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? value)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
