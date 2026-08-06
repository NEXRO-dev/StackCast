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

enum SharedArticleRepository {
    static let appGroupIdentifier = "group.com.nexro.Tsundoku"
    private static let articlesKey = "savedArticles"

    static func load() -> [SavedArticle] {
        guard
            let defaults,
            let data = defaults.data(forKey: articlesKey),
            let articles = try? JSONDecoder().decode([SavedArticle].self, from: data)
        else {
            return []
        }

        return articles.sorted { $0.savedAt > $1.savedAt }
    }

    @discardableResult
    static func save(url: URL, title: String? = nil) -> SavedArticle? {
        guard let defaults, let normalizedURL = normalizedWebURL(from: url) else { return nil }

        let resolvedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = resolvedTitle.flatMap { $0.isEmpty ? nil : $0 }
            ?? normalizedURL.host()
            ?? normalizedURL.absoluteString
        let article = SavedArticle(
            id: UUID(),
            url: normalizedURL,
            title: displayTitle,
            source: normalizedURL.host() ?? normalizedURL.absoluteString,
            savedAt: .now,
            state: .unread,
            completedAt: nil
        )

        var articles = load()
        articles.removeAll { normalizedWebURL(from: $0.url) == normalizedURL }
        articles.insert(article, at: 0)

        guard let data = try? JSONEncoder().encode(articles) else { return nil }
        defaults.set(data, forKey: articlesKey)
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
        guard SharedArticleRepository.save(url: url, title: title) != nil else { return false }
        refresh()
        return true
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
