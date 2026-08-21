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

struct CastRecord: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let summary: String?
    let transcript: String?
    let durationMinutes: Int
    let status: String
    let audioURL: URL?
    let creditCost: Int
    let errorMessage: String?
    let createdAt: String
    let completedAt: String?
    let shareToken: String?
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

    func merged(with remoteCasts: [CastRecord]) -> [CastRecord] {
        var merged = remoteCasts
        let remoteIDs = Set(remoteCasts.map(\.id))
        merged.append(contentsOf: downloadedCasts.filter { !remoteIDs.contains($0.id) })
        return merged
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
    private(set) var isLoading = false
    private(set) var isGenerating = false
    private(set) var errorMessage: String?
    private(set) var errorCode: String?
    private(set) var pendingOpenCastID: String?

    init() {
        casts = CastDownloadStore.shared.downloadedCasts
    }

    func clear() {
        casts = []
        errorMessage = nil
        errorCode = nil
        isLoading = false
        isGenerating = false
        pendingOpenCastID = nil
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
            casts = CastDownloadStore.shared.merged(with: loadedCasts)
#if CAST_LIVE_ACTIVITY_APP
            CastGenerationActivityStore.shared.sync(with: loadedCasts)
#endif
            errorMessage = nil
            errorCode = nil
        } catch {
            casts = CastDownloadStore.shared.merged(with: casts)
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
        defer { isGenerating = false }

        do {
            let cast = try await CastAPI.create(
                token: token,
                durationMinutes: durationMinutes,
                sources: sources
            )
            casts.insert(cast, at: 0)
#if CAST_LIVE_ACTIVITY_APP
            CastGenerationActivityStore.shared.start(for: cast)
#endif
            errorMessage = nil
            return cast
        } catch {
            errorMessage = error.localizedDescription
            errorCode = (error as NSError).userInfo["CastAPIErrorCode"] as? String
            return nil
        }
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

    func start(for cast: CastRecord) {
        guard cast.status == "queued" || cast.status == "processing",
              ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if activity != nil { return }
        let attributes = CastGenerationActivityAttributes(castTitle: cast.title, subtitle: "StackCast")
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: .init(status: "Cast準備中..."), staleDate: Date(timeIntervalSinceNow: 30 * 60)),
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
        let status = language == .english ? "Cast preparing..." : "Cast準備中..."
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: .init(status: status), staleDate: Date(timeIntervalSinceNow: 30 * 60)),
                pushType: nil
            )
            isPreviewing = true
        } catch {
            print("[cast] preview Live Activity failed: \(error)")
        }
    }

    func stopPreview() {
        guard isPreviewing, let activity else { return }
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
        let pending = casts.first(where: { $0.title == activity.attributes.castTitle && ($0.status == "queued" || $0.status == "processing") })
        guard pending == nil else { return }
        Task {
            await activity.end(
                ActivityContent(state: .init(status: "完了"), staleDate: nil),
                dismissalPolicy: .after(.now + 2)
            )
        }
        self.activity = nil
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
