//
//  ArticleLibrary.swift
//  Tsundoku
//

import Foundation
#if CAST_LIVE_ACTIVITY_APP
import ActivityKit
#endif
import LinkPresentation
import Observation
import UIKit
import UserNotifications

@MainActor
final class PushDeviceTokenRegistration {
    static let shared = PushDeviceTokenRegistration()
    private let tokenKey = "stackcast.apns.device-token"
    private var deviceToken: String?

    private init() {
        deviceToken = UserDefaults.standard.string(forKey: tokenKey)
    }

    func didRegister(_ data: Data) {
        let token = data.map { String(format: "%02x", $0) }.joined()
        guard !token.isEmpty else { return }
        deviceToken = token
        UserDefaults.standard.set(token, forKey: tokenKey)
    }

    func registerIfPossible(sessionToken: String?) {
        guard let sessionToken, !sessionToken.isEmpty, let deviceToken else { return }
        Task {
            var request = URLRequest(url: Config.apiBaseURL.appending(path: "notifications/device-token"))
            request.httpMethod = "POST"
            request.timeoutInterval = 15
            request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
#if DEBUG
            let environment = "sandbox"
#else
            let environment = "production"
#endif
            request.httpBody = try? JSONSerialization.data(withJSONObject: [
                "token": deviceToken,
                "environment": environment,
            ])
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                guard let response = response as? HTTPURLResponse,
                      (200..<300).contains(response.statusCode) else {
                    print("[push] device token registration failed")
                    return
                }
                print("[push] device token registered")
            } catch {
                print("[push] device token registration request failed: \(error.localizedDescription)")
            }
        }
    }
}

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
        switch self {
        case .free: 10
        case .plus: 100
        case .pro, .lifetime: nil
        }
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
    private static let articlesOwnerUserIDKey = "savedArticlesOwnerUserID"
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

    /// Activates the signed-in user's local cache. A shared app-group snapshot
    /// without a matching owner must never be uploaded to another account.
    @discardableResult
    static func activateCache(for userID: String) -> Bool {
        guard let defaults else { return false }
        let previousOwner = defaults.string(forKey: articlesOwnerUserIDKey)
        guard previousOwner != userID else { return false }

        defaults.removeObject(forKey: articlesKey)
        defaults.set(userID, forKey: articlesOwnerUserIDKey)
        return true
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
    private var serverSyncAttempted = false
    private var serverSyncToken: String?
    private var serverSyncUserID: String?

    init() {
        refresh()
    }

    func refresh() {
        articles = SharedArticleRepository.load()
        metadataTask?.cancel()
        metadataTask = Task { await enrichMissingTitles() }
    }

    /// Fetches the signed-in user's stock once per app session. Local data is
    /// used as an offline fallback and is uploaded only when the server is empty.
    func syncIfNeeded(token: String?, userID: String) async {
        if serverSyncUserID != userID {
            serverSyncAttempted = false
            serverSyncToken = nil
            serverSyncUserID = userID
            if SharedArticleRepository.activateCache(for: userID) {
                refresh()
            }
        }

        guard !serverSyncAttempted, let token, !token.isEmpty else { return }
        serverSyncAttempted = true
        serverSyncToken = token

        let localArticles = articles
        do {
            let remoteArticles = try await StockAPI.fetch(token: token)
            if remoteArticles.isEmpty, !localArticles.isEmpty {
                let saved = try await StockAPI.replace(token: token, articles: localArticles)
                replaceLocalArticles(saved)
            } else {
                replaceLocalArticles(remoteArticles)
            }
        } catch {
            print("[stock] initial sync failed: \(error.localizedDescription)")
        }
    }

    func resetServerSync() {
        serverSyncAttempted = false
        serverSyncToken = nil
        serverSyncUserID = nil
    }

    /// Supplies the current app-session token for later mutation syncs.
    /// ShareExtension can use the same shared library without needing the
    /// main-app-only AuthTokenStore; when no token is supplied, sync is skipped.
    func setServerSyncToken(_ token: String?) {
        serverSyncToken = token
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
            pushCurrentStateToServer()
        }
        return result
    }

    func mark(_ articleID: UUID, as state: SavedArticleState) {
        guard SharedArticleRepository.updateState(state, for: articleID) else { return }
        refresh()
        pushCurrentStateToServer()
    }

    func delete(_ articleID: UUID) {
        guard SharedArticleRepository.delete(id: articleID) else { return }
        refresh()
        pushCurrentStateToServer()
    }

    private func replaceLocalArticles(_ remoteArticles: [SavedArticle]) {
        articles = remoteArticles
        guard let defaults = UserDefaults(suiteName: SharedArticleRepository.appGroupIdentifier),
              let data = try? JSONEncoder().encode(remoteArticles) else { return }
        defaults.set(data, forKey: "savedArticles")
    }

    private func pushCurrentStateToServer() {
        guard let token = serverSyncToken, !token.isEmpty else { return }
        let snapshot = articles
        Task {
            do { _ = try await StockAPI.replace(token: token, articles: snapshot) }
            catch { print("[stock] update failed: \(error.localizedDescription)") }
        }
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

private enum StockAPI {
    private struct Response: Decodable {
        let items: [Item]
    }

    private struct Item: Codable {
        let id: String
        let url: String
        let title: String
        let source: String
        let savedAt: String
        let state: SavedArticleState
        let completedAt: String?
        let updatedAt: String?
    }

    static func fetch(token: String) async throws -> [SavedArticle] {
        var request = URLRequest(url: Config.apiBaseURL.appending(path: "stock"))
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data)
        return try decode(Response.self, from: data).items.compactMap(makeArticle)
    }

    static func replace(token: String, articles: [SavedArticle]) async throws -> [SavedArticle] {
        var request = URLRequest(url: Config.apiBaseURL.appending(path: "stock"))
        request.httpMethod = "PUT"
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "items": articles.map { article in
                Item(
                    id: article.id.uuidString,
                    url: article.url.absoluteString,
                    title: article.title,
                    source: article.source,
                    savedAt: iso8601.string(from: article.savedAt),
                    state: article.state,
                    completedAt: article.completedAt.map { iso8601.string(from: $0) },
                    updatedAt: iso8601.string(from: article.completedAt ?? article.savedAt)
                )
            }
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data)
        return try decode(Response.self, from: data).items.compactMap(makeArticle)
    }

    private static func makeArticle(_ item: Item) -> SavedArticle? {
        guard let id = UUID(uuidString: item.id),
              let url = URL(string: item.url),
              let savedAt = iso8601.date(from: item.savedAt) else { return nil }
        return SavedArticle(
            id: id,
            url: url,
            title: item.title,
            source: item.source,
            savedAt: savedAt,
            state: item.state,
            completedAt: item.completedAt.flatMap(iso8601.date)
        )
    }

    private static func validate(_ response: URLResponse, data: Data) throws {
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

struct CastRecord: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let summary: String?
    let transcript: String?
    let durationMinutes: Int
    let status: String
    let progressPercent: Int
    let audioURL: URL?
    let artworkURL: URL?
    let creditCost: Int
    let errorMessage: String?
    let createdAt: String
    let completedAt: String?
    let shareToken: String?

    private enum CodingKeys: String, CodingKey {
        case id, title, summary, transcript, durationMinutes, status, progressPercent
        case audioURL, artworkURL, creditCost, errorMessage, createdAt, completedAt, shareToken
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        transcript = try container.decodeIfPresent(String.self, forKey: .transcript)
        durationMinutes = try container.decode(Int.self, forKey: .durationMinutes)
        status = try container.decode(String.self, forKey: .status)
        progressPercent = try container.decodeIfPresent(Int.self, forKey: .progressPercent) ?? 0
        audioURL = try container.decodeIfPresent(URL.self, forKey: .audioURL)
        artworkURL = try container.decodeIfPresent(URL.self, forKey: .artworkURL)
        creditCost = try container.decode(Int.self, forKey: .creditCost)
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        completedAt = try container.decodeIfPresent(String.self, forKey: .completedAt)
        shareToken = try container.decodeIfPresent(String.self, forKey: .shareToken)
    }
}

@MainActor
@Observable
final class CastDownloadStore {
    static let shared = CastDownloadStore()

    private struct DownloadedCast: Codable {
        let cast: CastRecord
        let fileName: String
    }

    private(set) var downloadingCastIDs: Set<String> = []
    private(set) var lastErrorCastID: String?
    private var downloads: [String: DownloadedCast] = [:]

    private let fileManager = FileManager.default

    private init() {
        loadIndex()
    }

    var downloadedCasts: [CastRecord] {
        downloads.values.map(\.cast)
    }

    func isDownloaded(_ cast: CastRecord) -> Bool {
        audioURL(for: cast) != nil
    }

    func isDownloading(_ cast: CastRecord) -> Bool {
        downloadingCastIDs.contains(cast.id)
    }

    func audioURL(for cast: CastRecord) -> URL? {
        guard let download = downloads[cast.id] else { return nil }
        let url = downloadsDirectory.appending(path: download.fileName)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return url
    }

    func download(_ cast: CastRecord) async -> Bool {
        guard !isDownloaded(cast),
              !isDownloading(cast),
              let remoteURL = cast.audioURL else { return isDownloaded(cast) }

        downloadingCastIDs.insert(cast.id)
        lastErrorCastID = nil
        defer { downloadingCastIDs.remove(cast.id) }

        do {
            let (temporaryURL, response) = try await URLSession.shared.download(from: remoteURL)
            if let response = response as? HTTPURLResponse,
               !(200..<300).contains(response.statusCode) {
                throw URLError(.badServerResponse)
            }

            try createDownloadsDirectoryIfNeeded()
            let fileName = localFileName(for: cast, remoteURL: remoteURL)
            let destinationURL = downloadsDirectory.appending(path: fileName)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            try? fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: destinationURL.path
            )

            downloads[cast.id] = DownloadedCast(cast: cast, fileName: fileName)
            try persistIndex()
            return true
        } catch {
            lastErrorCastID = cast.id
            return false
        }
    }

    func removeDownload(for cast: CastRecord) {
        guard let download = downloads.removeValue(forKey: cast.id) else { return }
        let url = downloadsDirectory.appending(path: download.fileName)
        try? fileManager.removeItem(at: url)
        try? persistIndex()
    }

    private var downloadsDirectory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "DownloadedCasts", directoryHint: .isDirectory)
    }

    private var indexURL: URL {
        downloadsDirectory.appending(path: "index.json")
    }

    private func createDownloadsDirectoryIfNeeded() throws {
        try fileManager.createDirectory(
            at: downloadsDirectory,
            withIntermediateDirectories: true
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var directory = downloadsDirectory
        try? directory.setResourceValues(values)
    }

    private func localFileName(for cast: CastRecord, remoteURL: URL) -> String {
        let safeID = cast.id.replacingOccurrences(
            of: "[^A-Za-z0-9_-]",
            with: "_",
            options: .regularExpression
        )
        let remoteExtension = remoteURL.pathExtension.lowercased()
        let fileExtension = remoteExtension.isEmpty ? "audio" : remoteExtension
        return "\(safeID).\(fileExtension)"
    }

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL),
              let stored = try? JSONDecoder().decode([DownloadedCast].self, from: data) else {
            return
        }

        downloads = Dictionary(uniqueKeysWithValues: stored.compactMap { download in
            let url = downloadsDirectory.appending(path: download.fileName)
            return fileManager.fileExists(atPath: url.path)
                ? (download.cast.id, download)
                : nil
        })
    }

    private func persistIndex() throws {
        try createDownloadsDirectoryIfNeeded()
        let data = try JSONEncoder().encode(Array(downloads.values))
        try data.write(to: indexURL, options: .atomic)
    }
}

private struct CastSourceRequest: Encodable {
    let url: URL
    let title: String
}

private struct CastListResponse: Decodable {
    let casts: [CastRecord]
}

private struct CastCreateResponse: Decodable {
    let cast: CastRecord
}

private struct CastShareResponse: Decodable {
    let shareURL: URL
}

private struct CastAPIErrorResponse: Decodable {
    let error: APIError

    struct APIError: Decodable {
        let code: String
        let message: String
    }
}

@MainActor
@Observable
final class CastStore {
    private(set) var casts: [CastRecord] = []
    private(set) var sharedCastIDs: Set<String> = []
    private(set) var isLoading = false
    private(set) var isGenerating = false
    private(set) var errorMessage: String?
    private(set) var errorCode: String?
    private(set) var pendingOpenCastID: String?
    private(set) var lastCompletedCastID: String?
    private(set) var lastFailedCastID: String?
    private var generationTask: Task<Void, Never>?
    private var generatingCastID: String?

    func clear() {
        generationTask?.cancel()
        generationTask = nil
        casts = []
        sharedCastIDs = []
        errorMessage = nil
        errorCode = nil
        isLoading = false
        isGenerating = false
        pendingOpenCastID = nil
        generatingCastID = nil
    }

    func load(token: String?) async {
        guard let token else {
            clear()
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let pendingSharedCast = pendingOpenCastID.flatMap { pendingID in
                casts.first(where: { $0.id == pendingID })
            }
            var loadedCasts = try await CastAPI.list(token: token)
            if let pendingSharedCast,
               !loadedCasts.contains(where: { $0.id == pendingSharedCast.id }) {
                loadedCasts.insert(pendingSharedCast, at: 0)
            }
            // The Cast screen is server-authoritative. Local downloads are only
            // used as an audio source for a Cast that already exists in this
            // account's server response.
            casts = loadedCasts
            if let pending = loadedCasts.first(where: { $0.status == "queued" || $0.status == "processing" }) {
                isGenerating = true
                startGenerationMonitor(castID: pending.id, token: token)
            }
#if CAST_LIVE_ACTIVITY_APP
            CastGenerationActivityStore.shared.sync(with: loadedCasts)
#endif
            errorMessage = nil
            errorCode = nil
        } catch {
            // Never fall back to another account's local Cast index.
            // Keep the last server-backed list for a transient refresh error.
            errorMessage = "Castの読み込みに失敗しました。"
        }
    }

    func create(
        token: String?,
        durationMinutes: Int = 10,
        sources: [SavedArticle]
    ) async -> CastRecord? {
        guard let token else {
            errorMessage = "ログインが必要です。"
            return nil
        }

        isGenerating = true

        do {
            let cast = try await CastAPI.create(
                token: token,
                durationMinutes: durationMinutes,
                sources: sources
            )
            casts.insert(cast, at: 0)
            errorMessage = nil
            errorCode = nil

            if cast.status == "queued" || cast.status == "processing" {
                generatingCastID = cast.id
#if CAST_LIVE_ACTIVITY_APP
                CastGenerationActivityStore.shared.start(for: cast)
#endif
                startGenerationMonitor(castID: cast.id, token: token)
            } else if cast.status == "completed" {
                finishGeneration(with: cast)
            } else {
                failGeneration(with: cast)
            }
            return cast
        } catch {
            isGenerating = false
            errorMessage = error.localizedDescription
            errorCode = (error as NSError).userInfo["CastAPIErrorCode"] as? String
            return nil
        }
    }

    private func startGenerationMonitor(castID: String, token: String) {
        generationTask?.cancel()
        generatingCastID = castID
        generationTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled,
                      let latest = try? await CastAPI.list(token: token),
                      let updated = latest.first(where: { $0.id == castID })
                else { continue }

                self?.updateGeneration(with: updated)
                if updated.status == "completed" || updated.status == "failed" {
                    break
                }
            }
        }
    }

    private func updateGeneration(with cast: CastRecord) {
        if let index = casts.firstIndex(where: { $0.id == cast.id }) {
            casts[index] = cast
        } else {
            casts.insert(cast, at: 0)
        }

        switch cast.status {
        case "queued", "processing":
#if CAST_LIVE_ACTIVITY_APP
            CastGenerationActivityStore.shared.update(for: cast)
#endif
        case "completed":
            finishGeneration(with: cast)
        case "failed":
            failGeneration(with: cast)
        default:
            break
        }
    }

    private func finishGeneration(with cast: CastRecord) {
        generationTask?.cancel()
        generationTask = nil
        generatingCastID = nil
        isGenerating = false
        lastCompletedCastID = cast.id
#if CAST_LIVE_ACTIVITY_APP
        CastGenerationActivityStore.shared.complete(for: cast)
#endif
    }

    private func failGeneration(with cast: CastRecord) {
        generationTask?.cancel()
        generationTask = nil
        generatingCastID = nil
        isGenerating = false
        errorMessage = cast.errorMessage ?? "Castの作成に失敗しました。"
        lastFailedCastID = cast.id
#if CAST_LIVE_ACTIVITY_APP
        CastGenerationActivityStore.shared.fail()
#endif
    }

    func createShareURL(token: String?, castID: String) async -> URL? {
        guard let token else {
            errorMessage = "ログインが必要です。"
            return nil
        }

        do {
            let shareURL = try await CastAPI.createShareURL(token: token, castID: castID)
            errorMessage = nil
            errorCode = nil
            return shareURL
        } catch {
            errorMessage = "共有リンクを作成できませんでした。"
            errorCode = "share_failed"
            return nil
        }
    }

    func revokeShare(token: String?, castID: String) async -> Bool {
        guard let token else { return false }
        do {
            try await CastAPI.revokeShare(token: token, castID: castID)
            return true
        } catch {
            errorMessage = "共有リンクを停止できませんでした。"
            errorCode = "share_revoke_failed"
            return false
        }
    }

    func reportSharedCast(shareToken: String, reason: String, details: String?) async -> Bool {
        do {
            try await CastAPI.reportSharedCast(shareToken: shareToken, reason: reason, details: details)
            return true
        } catch {
            errorMessage = "通報を送信できませんでした。"
            errorCode = "report_failed"
            return false
        }
    }

    func openSharedCast(shareToken: String) async -> Bool {
        do {
            let cast = try await CastAPI.publicCast(shareToken: shareToken)
            casts.removeAll { $0.id == cast.id }
            casts.insert(cast, at: 0)
            sharedCastIDs.insert(cast.id)
            pendingOpenCastID = cast.id
            errorMessage = nil
            errorCode = nil
            return true
        } catch {
            errorMessage = "共有されたCastを開けませんでした。"
            errorCode = "shared_cast_failed"
            return false
        }
    }

    func consumePendingOpenCast() {
        pendingOpenCastID = nil
    }
}

#if CAST_LIVE_ACTIVITY_APP
@MainActor
final class CastGenerationActivityStore {
    static let shared = CastGenerationActivityStore()
    static let previewEnabledKey = "castGenerationLiveActivityPreviewEnabled"
    private var activity: Activity<CastGenerationActivityAttributes>?
    private var isPreviewing = false
    private var previewTask: Task<Void, Never>?

    func start(for cast: CastRecord) {
        guard cast.status == "queued" || cast.status == "processing" else { return }
        start(title: cast.title, progressPercent: cast.progressPercent)
    }

    func start(title: String, progressPercent: Int = 0) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        requestNotificationPermission()
        if activity != nil { return }
        let attributes = CastGenerationActivityAttributes(castTitle: title, subtitle: "StackCast")
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: .init(status: "Cast作成中", progressPercent: progressPercent), staleDate: Date(timeIntervalSinceNow: 30 * 60)),
                pushType: nil
            )
        } catch {
            print("[cast] generation Live Activity failed: \(error)")
        }
    }

    func startPreview(language: AppLanguage) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard activity == nil else { return }
        stopPreview()
        let attributes = CastGenerationActivityAttributes(
            castTitle: language == .english ? "Sample Cast generation" : "サンプルCastを生成中",
            subtitle: "StackCast"
        )
        let status = language == .english ? "Creating Cast" : "Cast作成中"
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: .init(status: status, progressPercent: 0), staleDate: Date(timeIntervalSinceNow: 30 * 60)),
                pushType: nil
            )
            isPreviewing = true
            previewTask = Task { [weak self] in
                var progress = 0
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    guard !Task.isCancelled, let self, let activity = self.activity else { break }
                    progress = min(progress + 1, 99)
                    await activity.update(
                        ActivityContent(
                            state: .init(status: status, progressPercent: progress),
                            staleDate: Date(timeIntervalSinceNow: 30 * 60)
                        )
                    )
                }
            }
        } catch {
            print("[cast] preview Live Activity failed: \(error)")
        }
    }

    func update(for cast: CastRecord) {
        guard let activity, !isPreviewing else { return }
        Task {
            await activity.update(
                ActivityContent(
                    state: .init(status: "Cast作成中", progressPercent: cast.progressPercent),
                    staleDate: Date(timeIntervalSinceNow: 30 * 60)
                )
            )
        }
    }

    func complete(for cast: CastRecord) {
        guard let activity, !isPreviewing else { return }
        Task {
            await activity.end(
                ActivityContent(state: .init(status: "Cast作成済み", progressPercent: 100, isCompleted: true), staleDate: nil),
                dismissalPolicy: .after(.now + 8)
            )
        }
        self.activity = nil
    }

    func fail() {
        guard let activity, !isPreviewing else { return }
        Task {
            await activity.end(
                ActivityContent(state: .init(status: "Castの作成に失敗しました", progressPercent: 0), staleDate: nil),
                dismissalPolicy: .after(.now + 4)
            )
        }
        self.activity = nil
    }

    func stopPreview() {
        guard isPreviewing, let activity else { return }
        previewTask?.cancel()
        previewTask = nil
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        self.activity = nil
        isPreviewing = false
    }

    func sync(with casts: [CastRecord]) {
        guard !isPreviewing else { return }
        guard let activity else {
            if let pending = casts.first(where: { $0.status == "queued" || $0.status == "processing" }) {
                start(for: pending)
            }
            return
        }
        guard let matchingCast = casts.first(where: { $0.title == activity.attributes.castTitle }) else { return }
        if matchingCast.status == "queued" || matchingCast.status == "processing" {
            update(for: matchingCast)
        } else if matchingCast.status == "completed" {
            complete(for: matchingCast)
        }
    }

    private func requestNotificationPermission() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }
}
#endif

private enum CastAPI {
    private static let baseURL = Config.backendBaseURL

    static func list(token: String) async throws -> [CastRecord] {
        let request = try makeRequest(path: "api/casts", method: "GET", token: token)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(CastListResponse.self, from: data).casts
    }

    static func create(
        token: String,
        durationMinutes: Int,
        sources: [SavedArticle]
    ) async throws -> CastRecord {
        let body: [String: AnyEncodable] = [
            "durationMinutes": AnyEncodable(durationMinutes),
            "sources": AnyEncodable(sources.map {
                CastSourceRequest(url: $0.url, title: $0.title)
            }),
        ]
        let request = try makeRequest(
            path: "api/casts",
            method: "POST",
            token: token,
            body: body
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(CastCreateResponse.self, from: data).cast
    }

    static func createShareURL(token: String, castID: String) async throws -> URL {
        let request = try makeRequest(
            path: "api/casts/\(castID)/share",
            method: "POST",
            token: token
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(CastShareResponse.self, from: data).shareURL
    }

    static func revokeShare(token: String, castID: String) async throws {
        let request = try makeRequest(path: "api/casts/\(castID)/share", method: "DELETE", token: token)
        let (_, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: Data())
    }

    static func reportSharedCast(shareToken: String, reason: String, details: String?) async throws {
        var request = URLRequest(url: baseURL.appending(path: "api/public/casts/\(shareToken)/report"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(CastReportRequest(reason: reason, details: details))
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
    }

    static func publicCast(shareToken: String) async throws -> CastRecord {
        var request = URLRequest(
            url: baseURL.appending(path: "api/public/casts/\(shareToken)")
        )
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(CastCreateResponse.self, from: data).cast
    }

    private static func makeRequest(
        path: String,
        method: String,
        token: String,
        body: [String: AnyEncodable]? = nil
    ) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private static func validate(response: URLResponse, data: Data) throws {
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            if let payload = try? JSONDecoder().decode(CastAPIErrorResponse.self, from: data) {
                throw NSError(domain: "CastAPI", code: responseCode(response), userInfo: [
                    NSLocalizedDescriptionKey: payload.error.message,
                    "CastAPIErrorCode": payload.error.code,
                ])
            }
            throw NSError(domain: "CastAPI", code: responseCode(response), userInfo: [
                NSLocalizedDescriptionKey: "Castを作成できませんでした。",
            ])
        }
    }

    private static func responseCode(_ response: URLResponse) -> Int {
        (response as? HTTPURLResponse)?.statusCode ?? -1
    }
}

private struct AnyEncodable: Encodable {
    private let encodeValue: (Encoder) throws -> Void

    init<T: Encodable>(_ value: T) {
        encodeValue = value.encode(to:)
    }

    func encode(to encoder: Encoder) throws {
        try encodeValue(encoder)
    }
}

private struct CastReportRequest: Encodable {
    let reason: String
    let details: String?
}
