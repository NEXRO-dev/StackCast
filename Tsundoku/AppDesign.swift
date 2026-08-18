//
//  AppDesign.swift
//  Tsundoku
//

import SwiftUI
import SafariServices

enum AppLanguage: String, CaseIterable, Identifiable {
    static let storageKey = "appLanguage"

    case japanese
    case english

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .japanese: "日本語"
        case .english: "English"
        }
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    static let storageKey = "appAppearance"

    case system
    case light
    case dark

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    func displayName(isEnglish: Bool) -> String {
        switch self {
        case .system: isEnglish ? "System" : "システム"
        case .light: isEnglish ? "Light" : "ライト"
        case .dark: isEnglish ? "Dark" : "ダーク"
        }
    }
}

enum AppDesign {
    static let pagePadding: CGFloat = 20
    static let cardRadius: CGFloat = 22
}

struct InAppBrowserDestination: Identifiable {
    let url: URL

    var id: URL { url }
}

struct InAppBrowserView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ viewController: SFSafariViewController, context: Context) {}
}

struct AccountAvatarView: View {
    let user: AuthUser

    var body: some View {
        ZStack {
            Circle()
                .fill(.indigo.opacity(0.14))

            if let profileImageURL = user.profileImageURL {
                AsyncImage(url: profileImageURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .controlSize(.small)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        fallback
                    @unknown default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(.primary.opacity(0.08), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var fallback: some View {
        if let initial = user.name.first {
            Text(String(initial).uppercased())
                .font(.title3.bold())
                .foregroundStyle(.indigo)
        } else {
            Image(systemName: "person.fill")
                .foregroundStyle(.indigo)
        }
    }
}

struct MockArticle: Identifiable {
    let id: UUID
    let title: String
    let source: String
    let readingTime: Int?
    let deadlineText: String
    let status: ArticleStatus
    let symbol: String
    let color: Color
    let originalURL: URL?

    init(
        id: UUID = UUID(),
        title: String,
        source: String,
        readingTime: Int?,
        deadlineText: String,
        status: ArticleStatus,
        symbol: String,
        color: Color,
        originalURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.source = source
        self.readingTime = readingTime
        self.deadlineText = deadlineText
        self.status = status
        self.symbol = symbol
        self.color = color
        self.originalURL = originalURL
    }

    static let samples = [
        MockArticle(
            title: "生成AI時代に変わる、プロダクトデザインの役割",
            source: "Design Journal",
            readingTime: 8,
            deadlineText: "残り1日",
            status: .unread,
            symbol: "wand.and.stars",
            color: .indigo
        ),
        MockArticle(
            title: "集中力を取り戻すための小さな習慣",
            source: "Life & Work",
            readingTime: 6,
            deadlineText: "残り2日",
            status: .inProgress,
            symbol: "brain.head.profile",
            color: .orange
        ),
        MockArticle(
            title: "音声コンテンツが生活に溶け込むまで",
            source: "Tech Review",
            readingTime: 11,
            deadlineText: "残り4日",
            status: .unread,
            symbol: "waveform",
            color: .teal
        ),
        MockArticle(
            title: "ニュースとの、ちょうどいい距離感",
            source: "Slow Media",
            readingTime: 5,
            deadlineText: "今日完了",
            status: .completed,
            symbol: "newspaper.fill",
            color: .pink
        ),
        MockArticle(
            title: "週末に読みたかった長いインタビュー",
            source: "People",
            readingTime: 14,
            deadlineText: "2日前に期限切れ",
            status: .expired,
            symbol: "person.wave.2.fill",
            color: .gray
        )
    ]

    static let englishSamples = [
        MockArticle(
            title: "How AI Is Redefining the Role of Product Design",
            source: "Design Journal",
            readingTime: 8,
            deadlineText: "1 day left",
            status: .unread,
            symbol: "wand.and.stars",
            color: .indigo
        ),
        MockArticle(
            title: "Small Habits That Help You Regain Focus",
            source: "Life & Work",
            readingTime: 6,
            deadlineText: "2 days left",
            status: .inProgress,
            symbol: "brain.head.profile",
            color: .orange
        ),
        MockArticle(
            title: "How Audio Content Became Part of Everyday Life",
            source: "Tech Review",
            readingTime: 11,
            deadlineText: "4 days left",
            status: .unread,
            symbol: "waveform",
            color: .teal
        ),
        MockArticle(
            title: "Finding a Healthier Distance from the News",
            source: "Slow Media",
            readingTime: 5,
            deadlineText: "Completed today",
            status: .completed,
            symbol: "newspaper.fill",
            color: .pink
        ),
        MockArticle(
            title: "The Long Interview You Meant to Read This Weekend",
            source: "People",
            readingTime: 14,
            deadlineText: "Expired 2 days ago",
            status: .expired,
            symbol: "person.wave.2.fill",
            color: .gray
        )
    ]
}

extension SavedArticle {
    func displayArticle(language: AppLanguage) -> MockArticle {
        let expirationDate = savedAt.addingTimeInterval(5 * 24 * 60 * 60)
        let isExpired = state != .completed && expirationDate <= .now
        let daysRemaining = max(0, Int(ceil(expirationDate.timeIntervalSinceNow / (24 * 60 * 60))))

        return MockArticle(
            id: id,
            title: title,
            source: source,
            readingTime: nil,
            deadlineText: deadlineText(language: language, daysRemaining: daysRemaining, isExpired: isExpired),
            status: displayStatus(isExpired: isExpired),
            symbol: "safari.fill",
            color: .blue,
            originalURL: url
        )
    }

    private func displayStatus(isExpired: Bool) -> ArticleStatus {
        if isExpired { return .expired }
        return switch state {
        case .unread: .unread
        case .inProgress: .inProgress
        case .completed: .completed
        }
    }

    private func deadlineText(language: AppLanguage, daysRemaining: Int, isExpired: Bool) -> String {
        if isExpired {
            return language == .english ? "Expired" : "期限切れ"
        }
        if daysRemaining == 1 {
            return language == .english ? "1 day left" : "残り1日"
        }
        return language == .english ? "\(daysRemaining) days left" : "残り\(daysRemaining)日"
    }
}

struct MockDigest: Identifiable, Hashable {
    let id: String
    let japaneseTitle: String
    let englishTitle: String
    let japaneseDate: String
    let englishDate: String
    let articleCount: Int
    let duration: String
    let progress: Double
    let symbol: String

    func title(for language: AppLanguage) -> String {
        language == .english ? englishTitle : japaneseTitle
    }

    func dateText(for language: AppLanguage) -> String {
        language == .english ? englishDate : japaneseDate
    }

    static let samples = [
        MockDigest(
            id: "morning-news",
            japaneseTitle: "朝のニュースCast",
            englishTitle: "Morning News Cast",
            japaneseDate: "今日 7:10に生成",
            englishDate: "Created today at 7:10",
            articleCount: 3,
            duration: "9:32",
            progress: 0.38,
            symbol: "sun.horizon.fill"
        ),
        MockDigest(
            id: "focus-before-work",
            japaneseTitle: "仕事前の集中力Cast",
            englishTitle: "Focus Before Work",
            japaneseDate: "昨日 8:05に生成",
            englishDate: "Created yesterday at 8:05",
            articleCount: 4,
            duration: "14:48",
            progress: 0,
            symbol: "brain.head.profile.fill"
        ),
        MockDigest(
            id: "weekend-long-reads",
            japaneseTitle: "週末のロングリード",
            englishTitle: "Weekend Long Reads",
            japaneseDate: "8月2日に生成",
            englishDate: "Created Aug 2",
            articleCount: 5,
            duration: "27:15",
            progress: 1,
            symbol: "books.vertical.fill"
        ),
        MockDigest(
            id: "technology-briefing",
            japaneseTitle: "テクノロジーまとめ",
            englishTitle: "Technology Briefing",
            japaneseDate: "8月1日に生成",
            englishDate: "Created Aug 1",
            articleCount: 2,
            duration: "6:44",
            progress: 1,
            symbol: "cpu.fill"
        ),
        MockDigest(
            id: "evening-briefing",
            japaneseTitle: "夕方のニュース振り返り",
            englishTitle: "Evening News Review",
            japaneseDate: "7月31日に生成",
            englishDate: "Created Jul 31",
            articleCount: 3,
            duration: "12:06",
            progress: 1,
            symbol: "sunset.fill"
        ),
        MockDigest(
            id: "design-weekly",
            japaneseTitle: "デザインウィークリー",
            englishTitle: "Design Weekly",
            japaneseDate: "7月29日に生成",
            englishDate: "Created Jul 29",
            articleCount: 4,
            duration: "18:20",
            progress: 0,
            symbol: "paintpalette.fill"
        ),
        MockDigest(
            id: "wellness-notes",
            japaneseTitle: "心と身体を整えるヒント",
            englishTitle: "Wellness Notes",
            japaneseDate: "7月28日に生成",
            englishDate: "Created Jul 28",
            articleCount: 2,
            duration: "7:55",
            progress: 1,
            symbol: "leaf.fill"
        )
    ]
}

enum ArticleStatus: String, CaseIterable {
    case unread = "未読"
    case inProgress = "進行中"
    case completed = "完了"
    case expired = "期限切れ"

    var color: Color {
        switch self {
        case .unread: .blue
        case .inProgress: .orange
        case .completed: .green
        case .expired: .secondary
        }
    }

    func title(for language: AppLanguage) -> String {
        guard language == .english else { return rawValue }

        return switch self {
        case .unread: "Unread"
        case .inProgress: "In Progress"
        case .completed: "Completed"
        case .expired: "Expired"
        }
    }
}

enum StockFilter: CaseIterable {
    case all
    case expiring
    case completed
}

struct ArticleArtwork: View {
    let article: MockArticle
    var size: CGFloat = 64

    var body: some View {
        ArticleFaviconView(
            url: article.originalURL,
            size: size,
            isArtwork: true,
            fallbackColor: article.color
        )
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct DigestTabAccessory: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    let language: AppLanguage
    let cast: CastRecord
    let playbackStore: CastPlaybackStore
    let subscriptionTier: SubscriptionPlanTier
    let openPlayer: () -> Void
    let close: () -> Void

    var body: some View {
        switch placement {
        case .expanded, .none:
            expandedAccessory
        case .inline:
            inlineAccessory
        @unknown default:
            expandedAccessory
        }
    }

    private var inlineAccessory: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                CastArtwork(cast: cast, size: 28)

                Text(cast.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: openPlayer)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(language == .english ? "Open Morning News Cast" : "朝のニュースCastを開く")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                openPlayer()
            }
            .frame(maxWidth: .infinity)
            .clipped()

            Image(systemName: playbackStore.isPlaying ? "pause.fill" : "play.fill")
                .font(.caption.weight(.bold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
                .onTapGesture {
                    togglePlayback()
                }
                .accessibilityElement()
                .accessibilityLabel(playbackAccessibilityLabel)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction {
                    togglePlayback()
                }
                .fixedSize()

            closeControl(size: 32, font: .caption.weight(.bold))
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
    }

    private var expandedAccessory: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                HStack(spacing: 12) {
                    digestArtwork

                    VStack(alignment: .leading, spacing: 3) {
                        Text(cast.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text("\(playbackStore.elapsedTime) / \(playbackStore.durationTime)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: openPlayer)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(language == .english ? "Open Morning News Cast" : "朝のニュースCastを開く")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction {
                    openPlayer()
                }
                .frame(maxWidth: .infinity)
                .clipped()

                Image(systemName: playbackStore.isPlaying ? "pause.fill" : "play.fill")
                    .font(.headline)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.snappy) {
                            togglePlayback()
                        }
                    }
                    .accessibilityElement()
                    .accessibilityLabel(playbackAccessibilityLabel)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction {
                        togglePlayback()
                    }
                    .fixedSize()

                closeControl(size: 44, font: .subheadline.weight(.semibold))
            }
            .padding(.horizontal, 12)
            .frame(height: 56)

            ProgressView(value: playbackStore.progress)
                .progressViewStyle(.linear)
                .tint(.indigo)
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity)
    }

    private var playbackAccessibilityLabel: String {
        language == .english
            ? (playbackStore.isPlaying ? "Pause" : "Play")
            : (playbackStore.isPlaying ? "一時停止" : "再生")
    }

    private func closeControl(size: CGFloat, font: Font) -> some View {
        Image(systemName: "xmark")
            .font(font)
            .frame(width: size, height: size)
            .contentShape(Rectangle())
            .onTapGesture(perform: close)
            .accessibilityElement()
            .accessibilityLabel(language == .english ? "Close player" : "プレイヤーを閉じる")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                close()
            }
            .fixedSize()
    }

    private var digestArtwork: some View {
        CastArtwork(cast: cast, size: 42)
    }

    private func togglePlayback() {
        playbackStore.toggle(cast, subscriptionTier: subscriptionTier)
    }
}

struct CastArtwork: View {
    let cast: CastRecord
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(LinearGradient(
                    colors: [.indigo, .purple.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))

            Image(systemName: "waveform")
                .font(.system(size: size * 0.34, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct GlassAddButton: View {
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.title2.bold())
                .foregroundStyle(.black)
                .frame(width: 54, height: 54)
                .contentShape(Circle())
                .modifier(WhiteGlassCircle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .shadow(color: .black.opacity(0.14), radius: 10, y: 5)
    }
}

private struct WhiteGlassCircle: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.tint(.white).interactive(), in: .circle)
        } else {
            content
                .background(.white, in: Circle())
                .overlay {
                    Circle().stroke(.black.opacity(0.08))
                }
        }
    }
}

struct DigestLibraryRow: View {
    let digest: MockDigest
    let language: AppLanguage

    var body: some View {
        HStack(spacing: 14) {
            artwork

            VStack(alignment: .leading, spacing: 6) {
                Text(digest.title(for: language))
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(metadata)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if digest.progress > 0, digest.progress < 1 {
                    ProgressView(value: digest.progress)
                        .tint(.indigo)
                } else {
                    Text(statusText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(digest.progress == 1 ? .green : .indigo)
                }
            }

            Spacer(minLength: 4)

            Image(systemName: digest.progress == 1 ? "checkmark.circle.fill" : "play.circle.fill")
                .font(.title2)
                .foregroundStyle(digest.progress == 1 ? .green : .indigo)
                .accessibilityHidden(true)
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(artworkColor.gradient)

            Image(systemName: digest.symbol)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 64, height: 64)
        .accessibilityHidden(true)
    }

    private var artworkColor: Color {
        switch digest.id {
        case "focus-before-work": .orange
        case "weekend-long-reads": .teal
        case "technology-briefing": .blue
        case "evening-briefing": .purple
        case "design-weekly": .pink
        case "wellness-notes": .green
        default: .indigo
        }
    }

    private var metadata: String {
        if language == .english {
            return "\(digest.articleCount) articles · \(digest.duration) · \(digest.dateText(for: language))"
        }
        return "\(digest.articleCount)記事 ・ \(digest.duration) ・ \(digest.dateText(for: language))"
    }

    private var statusText: String {
        if language == .english {
            return digest.progress == 1 ? "Completed" : "Not played"
        }
        return digest.progress == 1 ? "再生済み" : "未再生"
    }
}

struct PullDownToDismissPlayer<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    @State private var scrollOffset: CGFloat = 0
    @GestureState private var dragOffset: CGFloat = 0

    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Capsule()
                    .fill(.secondary.opacity(0.45))
                    .frame(width: 38, height: 5)
                    .padding(.top, 10)
                    .padding(.bottom, 5)
                    .accessibilityHidden(true)

                content
            }
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, newOffset in
            scrollOffset = newOffset
        }
        .background(playerBackground)
        .offset(y: dragOffset)
        .scaleEffect(1 - min(dragOffset / 6_000, 0.025), anchor: .center)
        .simultaneousGesture(dismissGesture)
        .accessibilityAction(.escape) {
            dismiss()
        }
    }

    private var playerBackground: some View {
        ZStack {
            Color(.systemBackground)

            LinearGradient(
                colors: [.indigo.opacity(0.16), .clear],
                startPoint: .top,
                endPoint: .center
            )
        }
        .ignoresSafeArea()
    }

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .updating($dragOffset) { value, state, _ in
                guard canStartDismissal(with: value) else { return }
                state = value.translation.height
            }
            .onEnded { value in
                guard canStartDismissal(with: value) else { return }

                if value.translation.height > 120 || value.predictedEndTranslation.height > 220 {
                    dismiss()
                }
            }
    }

    private func canStartDismissal(with value: DragGesture.Value) -> Bool {
        scrollOffset <= 1
            && value.translation.height > 0
            && abs(value.translation.height) > abs(value.translation.width)
    }
}

struct ArticleRow: View {
    let article: MockArticle
    var showsStatus = true
    var language: AppLanguage = .japanese

    var body: some View {
        HStack(spacing: 14) {
            ArticleArtwork(article: article)

            VStack(alignment: .leading, spacing: 6) {
                Text(article.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                Text(articleMetadata)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if showsStatus {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(article.status.color)
                            .frame(width: 6, height: 6)

                        Text(article.status.title(for: language))

                        Text("・")

                        Text(article.deadlineText)
                    }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(article.status == .expired ? .secondary : article.status.color)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var articleMetadata: String {
        guard let readingTime = article.readingTime else { return article.source }
        return language == .english
            ? "\(article.source) · \(readingTime) min"
            : "\(article.source) ・ \(readingTime)分"
    }
}

struct ArticleFaviconView: View {
    let url: URL?
    var size: CGFloat = 14
    var isArtwork = false
    var fallbackColor: Color = .blue

    var body: some View {
        AsyncImage(url: faviconURL) { phase in
            switch phase {
            case .success(let image):
                if isArtwork {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
                } else {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(width: size, height: size)
                }
            default:
                fallbackArtwork
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var fallbackArtwork: some View {
        if isArtwork {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                    .fill(fallbackColor.gradient)

                Image(systemName: "safari.fill")
                    .font(.system(size: size * 0.34, weight: .semibold))
                    .foregroundStyle(.white)
            }
        } else {
            Image(systemName: "safari.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(fallbackColor)
        }
    }

    private var faviconURL: URL? {
        guard let url, let host = url.host, !host.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = url.scheme ?? "https"
        components.host = host
        components.path = "/favicon.ico"
        return components.url
    }
}

struct DurationSegmentedControl: View {
    @Binding var selection: Int

    let durations: [Int]
    let customDuration: Int
    let language: AppLanguage
    let onCustomize: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Picker(language == .english ? "Cast duration" : "Cast時間", selection: $selection) {
                    ForEach(durations, id: \.self) { duration in
                        Text("\(duration)").tag(duration)
                    }

                    Image(systemName: "slider.horizontal.3")
                        .tag(-1)
                        .accessibilityHidden(true)
                }
                .pickerStyle(.segmented)

                HStack(spacing: 0) {
                    Color.clear
                        .frame(width: proxy.size.width * 0.8)
                        .allowsHitTesting(false)

                    Button {
                        selection = -1
                        onCustomize()
                    } label: {
                        Color.clear
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(language == .english
                                        ? "Customize duration. Currently \(customDuration) minutes"
                                        : "時間をカスタマイズ。現在は\(customDuration)分")
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        guard abs(value.translation.width) >= abs(value.translation.height) else { return }
                        selection = selectionValue(at: value.location.x, width: proxy.size.width)
                    }
                    .onEnded { value in
                        guard abs(value.translation.width) >= abs(value.translation.height) else { return }
                        let finalSelection = selectionValue(at: value.location.x, width: proxy.size.width)
                        selection = finalSelection
                        if finalSelection == -1 {
                            onCustomize()
                        }
                    }
            )
        }
        .frame(height: 32)
    }

    private func selectionValue(at locationX: CGFloat, width: CGFloat) -> Int {
        let rawIndex = Int(locationX / max(width, 1) * CGFloat(durations.count + 1))
        let index = min(durations.count, max(0, rawIndex))
        return index == durations.count ? -1 : durations[index]
    }

}

struct CustomDurationSheet: View {
    let language: AppLanguage
    let onSave: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var duration: Int

    init(language: AppLanguage, initialDuration: Int, onSave: @escaping (Int) -> Void) {
        self.language = language
        self.onSave = onSave
        _duration = State(initialValue: initialDuration)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                VStack(spacing: 6) {
                    Text("\(duration)")
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())

                    Text(language == .english ? "minutes" : "分")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                Slider(
                    value: Binding(
                        get: { Double(duration) },
                        set: { duration = Int($0) }
                    ),
                    in: 1...60,
                    step: 1
                )
            .accessibilityLabel(language == .english ? "Cast duration" : "Cast時間")
                .accessibilityValue(language == .english ? "\(duration) minutes" : "\(duration)分")

                HStack {
                    Text(language == .english ? "1 min" : "1分")
                    Spacer()
                    Text(language == .english ? "60 min" : "60分")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    durationButton(amount: -5, symbol: "minus")
                    durationButton(amount: 5, symbol: "plus")
                }

                Text(language == .english
                     ? "We'll create a Cast that fits within your selected time."
                     : "選択した時間に収まるCastを作成します。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .navigationTitle(language == .english ? "Custom Duration" : "時間をカスタマイズ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language == .english ? "Cancel" : "キャンセル") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(language == .english ? "Save" : "保存") {
                        onSave(duration)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func durationButton(amount: Int, symbol: String) -> some View {
        Button {
            withAnimation(.snappy) {
                duration = min(60, max(1, duration + amount))
            }
        } label: {
            Label("\(amount > 0 ? "+" : "")\(amount)", systemImage: symbol)
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled((amount < 0 && duration == 1) || (amount > 0 && duration == 60))
    }
}

extension View {
    func tsundokuCard() -> some View {
        padding(18)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: AppDesign.cardRadius, style: .continuous))
    }

    func detoxMetricCard(tint: Color) -> some View {
        padding(18)
            .background(
                Color(.systemBackground),
                in: RoundedRectangle(cornerRadius: AppDesign.cardRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppDesign.cardRadius, style: .continuous)
                    .stroke(tint.opacity(0.22), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.07), radius: 12, y: 5)
    }
}
