//
//  ArticleLibrary.swift
//  Tsundoku
//

import Foundation
import LinkPresentation
import Observation

enum SavedArticleState: String, Codable {
    case unread
    case inProgress
    case completed
}

struct SavedArticle: Codable, Identifiable, Equatable {
    let id: UUID
    let url: URL
    let title: String
    let source: String
    let savedAt: Date
    let state: SavedArticleState
    let completedAt: Date?

    init(
        id: UUID,
        url: URL,
        title: String,
        source: String,
        savedAt: Date,
        state: SavedArticleState = .unread,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.source = source
        self.savedAt = savedAt
        self.state = state
        self.completedAt = completedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, url, title, source, savedAt, state, completedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        url = try container.decode(URL.self, forKey: .url)
        title = try container.decode(String.self, forKey: .title)
        source = try container.decode(String.self, forKey: .source)
        savedAt = try container.decode(Date.self, forKey: .savedAt)
        state = try container.decodeIfPresent(SavedArticleState.self, forKey: .state) ?? .unread
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
    }
}

enum SharedSubscriptionTier: String, Equatable {
    case free
    case plus
    case pro
    case lifetime

    var activeArticleLimit: Int? {
        self == .free ? 10 : nil
    }

    var retentionInterval: TimeInterval? {
        switch self {
        case .free:
            5 * 24 * 60 * 60
        case .plus:
            15 * 24 * 60 * 60
        case .pro, .lifetime:
            nil
        }
    }
}

enum SharedArticleSaveResult {
    case saved(SavedArticle)
    case limitReached
    case invalidURL
    case failed
}

enum SharedArticleRepository {
    static let appGroupIdentifier = "group.com.nexro.Tsundoku"
    private static let articlesKey = "savedArticles"
    private static let subscriptionTierKey = "subscriptionTier"

    static func load() -> [SavedArticle] {
        guard
            let defaults,
            let data = defaults.data(forKey: articlesKey),
            let articles = try? JSONDecoder().decode([SavedArticle].self, from: data)
        else {
            return []
        }

        let validArticles = articles.filter { !isExpired($0) || $0.state == .completed }
        if validArticles.count != articles.count {
            _ = persist(validArticles, to: defaults)
        }

        return validArticles.sorted { $0.savedAt > $1.savedAt }
    }

    static var subscriptionTier: SharedSubscriptionTier {
        guard
            let defaults,
            let rawValue = defaults.string(forKey: subscriptionTierKey),
            let tier = SharedSubscriptionTier(rawValue: rawValue)
        else {
            return .free
        }

        return tier
    }

    static func setSubscriptionTier(_ tier: SharedSubscriptionTier) {
        defaults?.set(tier.rawValue, forKey: subscriptionTierKey)
    }

    static func saveWithLimit(url: URL, title: String? = nil) -> SharedArticleSaveResult {
        guard let defaults, let normalizedURL = normalizedWebURL(from: url) else {
            return .invalidURL
        }

        let resolvedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = resolvedTitle.flatMap { $0.isEmpty ? nil : $0 }
            ?? normalizedURL.host()
            ?? normalizedURL.absoluteString

        var articles = load()
        let isExistingArticle = articles.contains { normalizedWebURL(from: $0.url) == normalizedURL }
        if !isExistingArticle,
           let activeArticleLimit = subscriptionTier.activeArticleLimit {
            let activeArticleCount = articles.filter { $0.state != .completed }.count
            guard activeArticleCount < activeArticleLimit else {
                return .limitReached
            }
        }

        let article = SavedArticle(
            id: UUID(),
            url: normalizedURL,
            title: displayTitle,
            source: normalizedURL.host() ?? normalizedURL.absoluteString,
            savedAt: .now,
            state: .unread,
            completedAt: nil
        )

        articles.removeAll { normalizedWebURL(from: $0.url) == normalizedURL }
        articles.insert(article, at: 0)

        guard let data = try? JSONEncoder().encode(articles) else { return .failed }
        defaults.set(data, forKey: articlesKey)
        return .saved(article)
    }

    @discardableResult
    static func save(url: URL, title: String? = nil) -> SavedArticle? {
        guard case let .saved(article) = saveWithLimit(url: url, title: title) else { return nil }
        return article
    }

    @discardableResult
    static func updateTitle(_ title: String, for id: UUID) -> Bool {
        guard let defaults else { return false }

        var articles = load()
        guard let index = articles.firstIndex(where: { $0.id == id }) else { return false }

        let current = articles[index]
        articles[index] = SavedArticle(
            id: current.id,
            url: current.url,
            title: title,
            source: current.source,
            savedAt: current.savedAt,
            state: current.state,
            completedAt: current.completedAt
        )

        guard let data = try? JSONEncoder().encode(articles) else { return false }
        defaults.set(data, forKey: articlesKey)
        return true
    }

    @discardableResult
    static func updateState(_ state: SavedArticleState, for id: UUID) -> Bool {
        guard let defaults else { return false }

        var articles = load()
        guard let index = articles.firstIndex(where: { $0.id == id }) else { return false }

        let current = articles[index]
        articles[index] = SavedArticle(
            id: current.id,
            url: current.url,
            title: current.title,
            source: current.source,
            savedAt: current.savedAt,
            state: state,
            completedAt: state == .completed ? (current.completedAt ?? .now) : nil
        )
        return persist(articles, to: defaults)
    }

    @discardableResult
    static func delete(id: UUID) -> Bool {
        guard let defaults else { return false }
        var articles = load()
        let previousCount = articles.count
        articles.removeAll { $0.id == id }
        guard articles.count != previousCount else { return false }
        return persist(articles, to: defaults)
    }

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    private static func isExpired(_ article: SavedArticle) -> Bool {
        guard let retentionInterval = subscriptionTier.retentionInterval else { return false }
        return article.savedAt.addingTimeInterval(retentionInterval) < .now
    }

    private static func persist(_ articles: [SavedArticle], to defaults: UserDefaults) -> Bool {
        guard let data = try? JSONEncoder().encode(articles) else { return false }
        defaults.set(data, forKey: articlesKey)
        return true
    }

    private static func normalizedWebURL(from url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.fragment = nil
        return components.url
    }
}

@MainActor
@Observable
final class ArticleLibrary {
    private(set) var articles: [SavedArticle] = []
    private var metadataTask: Task<Void, Never>?

    init() {
        refresh()
    }

    func refresh() {
        articles = SharedArticleRepository.load()
        metadataTask?.cancel()
        metadataTask = Task { await enrichMissingTitles() }
    }

    @discardableResult
    func add(url: URL, title: String? = nil) -> Bool {
        switch addWithResult(url: url, title: title) {
        case .saved:
            return true
        case .limitReached, .invalidURL, .failed:
            return false
        }
    }

    func addWithResult(url: URL, title: String? = nil) -> SharedArticleSaveResult {
        let result = SharedArticleRepository.saveWithLimit(url: url, title: title)
        if case .saved = result {
            refresh()
        }
        return result
    }

    func mark(_ articleID: UUID, as state: SavedArticleState) {
        guard SharedArticleRepository.updateState(state, for: articleID) else { return }
        refresh()
    }

    func delete(_ articleID: UUID) {
        guard SharedArticleRepository.delete(id: articleID) else { return }
        refresh()
    }

    private func enrichMissingTitles() async {
        let unresolvedArticles = articles.filter { $0.title == $0.source }

        for article in unresolvedArticles {
            guard !Task.isCancelled else { return }
            let provider = LPMetadataProvider()

            guard
                let metadata = try? await provider.startFetchingMetadata(for: article.url),
                let title = metadata.title?.trimmingCharacters(in: .whitespacesAndNewlines),
                !title.isEmpty
            else {
                continue
            }

            if SharedArticleRepository.updateTitle(title, for: article.id) {
                articles = SharedArticleRepository.load()
            }
        }
    }
}
