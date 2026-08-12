//
//  PlayerView.swift
//  Tsundoku
//

import SwiftUI
import AVFoundation
import UIKit

struct PlayerView: View {
    let authStore: AuthStore
    let castStore: CastStore
    let playbackStore: CastPlaybackStore
    let subscriptionTier: SubscriptionPlanTier
    @Binding var selectedCast: CastRecord?
    @Binding var isDetailPresented: Bool

    var body: some View {
        CastListView(authStore: authStore, castStore: castStore, playbackStore: playbackStore, subscriptionTier: subscriptionTier, language: .japanese, selectedCast: $selectedCast, isDetailPresented: $isDetailPresented)
    }
}

struct CastListView: View {
    private enum CastCategory: CaseIterable {
        case all
        case unplayed
        case favorites
        case downloaded

        func title(for language: AppLanguage) -> String {
            switch (self, language) {
            case (.all, .english): "All"
            case (.all, _): "すべて"
            case (.unplayed, .english): "Unplayed"
            case (.unplayed, _): "未再生"
            case (.favorites, .english): "Favorites"
            case (.favorites, _): "お気に入り"
            case (.downloaded, .english): "Downloaded"
            case (.downloaded, _): "ダウンロード済み"
            }
        }
    }

    private enum CastSortOrder {
        case newest
        case oldest
    }

    let authStore: AuthStore
    let castStore: CastStore
    let playbackStore: CastPlaybackStore
    let subscriptionTier: SubscriptionPlanTier
    let language: AppLanguage
    @Binding var selectedCast: CastRecord?
    @Binding var isDetailPresented: Bool
    @State private var isSearchPresented = false
    @State private var searchText = ""
    @State private var sortOrder: CastSortOrder = .newest
    @State private var selectedCategory: CastCategory = .all
    @State private var sharePayload: CastSharePayload?
    @State private var isErrorPresented = false
    @FocusState private var isSearchFocused: Bool

    private var completedCasts: [CastRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = castStore.casts.filter { cast in
            cast.status == "completed"
                && cast.audioURL != nil
                && (query.isEmpty || cast.title.localizedCaseInsensitiveContains(query))
        }

        return filtered.sorted { lhs, rhs in
            switch sortOrder {
            case .newest:
                lhs.createdAt > rhs.createdAt
            case .oldest:
                lhs.createdAt < rhs.createdAt
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                podcastHeader

                if isSearchPresented {
                    searchBar
                        .padding(.horizontal, 20)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                categorySelector

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if completedCasts.isEmpty {
                            ContentUnavailableView {
                                Label(
                                    searchText.isEmpty
                                        ? (language == .english ? "No Casts" : "Castはありません")
                                        : (language == .english ? "No Results" : "検索結果はありません"),
                                    systemImage: searchText.isEmpty ? "waveform.circle" : "magnifyingglass"
                                )
                            } description: {
                                Text(searchText.isEmpty
                                     ? (language == .english
                                        ? "Generated audio Casts will appear here."
                                        : "生成された音声Castがここに表示されます。")
                                     : (language == .english
                                        ? "Try another keyword."
                                        : "別のキーワードで検索してください。"))
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            ForEach(completedCasts) { cast in
                                castRow(cast)

                                Divider()
                                    .padding(.leading, 78)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 110)
                }
            }
            .background(Color(.systemBackground).ignoresSafeArea())
        }
        .fullScreenCover(item: $selectedCast, onDismiss: {
            isDetailPresented = false
        }) { cast in
            CastDetailView(
                cast: cast,
                authStore: authStore,
                castStore: castStore,
                playbackStore: playbackStore,
                subscriptionTier: subscriptionTier,
                language: language
            )
            .presentationBackground(.clear)
        }
        .sheet(item: $sharePayload) { payload in
            SystemShareSheet(activityItems: [payload.url])
                .presentationDetents([.medium, .large])
        }
        .appErrorAlert(isPresented: $isErrorPresented, language: language)
        .onChange(of: castStore.pendingOpenCastID, initial: true) { _, castID in
            guard let castID,
                  let cast = castStore.casts.first(where: { $0.id == castID }) else { return }
            showDetails(for: cast)
            castStore.consumePendingOpenCast()
        }
    }

    private var podcastHeader: some View {
        HStack(spacing: 16) {
            Text(language == .english ? "Podcast" : "ポッドキャスト")
                .font(.title.weight(.bold))
                .lineLimit(1)

            Spacer(minLength: 8)

            headerActions
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    @ViewBuilder
    private var headerActions: some View {
        if #available(iOS 26.0, *) {
            compactHeaderActions
                .glassEffect(.regular.interactive(), in: .capsule)
        } else {
            compactHeaderActions
                .background(.ultraThinMaterial, in: Capsule())
        }
    }

    private var compactHeaderActions: some View {
        HStack(spacing: 2) {
            searchButton
            moreButton
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
    }

    private var searchButton: some View {
        Button {
            if isSearchPresented {
                closeSearch()
            } else {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                    isSearchPresented = true
                }
            }
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(language == .english ? "Search Casts" : "Castを検索")
    }

    private var moreButton: some View {
        Menu {
            Button {
                sortOrder = .newest
            } label: {
                Label(
                    language == .english ? "Newest First" : "新しい順",
                    systemImage: sortOrder == .newest ? "checkmark" : "arrow.down"
                )
            }

            Button {
                sortOrder = .oldest
            } label: {
                Label(
                    language == .english ? "Oldest First" : "古い順",
                    systemImage: sortOrder == .oldest ? "checkmark" : "arrow.up"
                )
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(language == .english ? "More options" : "その他のオプション")
    }

    @ViewBuilder
    private var searchBar: some View {
        let content = HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField(
                language == .english ? "Search Casts" : "Castを検索",
                text: $searchText
            )
            .focused($isSearchFocused)
            .submitLabel(.search)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            Button {
                closeSearch()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(language == .english ? "Close Search" : "検索を閉じる")
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .onAppear {
            isSearchFocused = true
        }

        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: .capsule)
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
        }
    }

    private func closeSearch() {
        isSearchFocused = false
        searchText = ""
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            isSearchPresented = false
        }
    }

    private var categorySelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            categoryChips
        }
        .contentMargins(.horizontal, 20, for: .scrollContent)
        .padding(.top, 2)
        .padding(.bottom, 12)
        .accessibilityLabel(language == .english ? "Cast categories" : "Castカテゴリー")
    }

    @ViewBuilder
    private var categoryChips: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 10) {
                    ForEach(CastCategory.allCases, id: \.self) { category in
                        categoryButton(category)
                    }
                }
            }
        } else {
            HStack(spacing: 10) {
                ForEach(CastCategory.allCases, id: \.self) { category in
                    categoryButton(category)
                }
            }
        }
    }

    @ViewBuilder
    private func categoryButton(_ category: CastCategory) -> some View {
        let isSelected = selectedCategory == category

        if #available(iOS 26.0, *) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                    selectedCategory = category
                }
            } label: {
                categoryLabel(category, isSelected: isSelected)
                    .glassEffect(
                        .regular
                            .tint(isSelected ? Color.indigo.opacity(0.78) : nil)
                            .interactive(),
                        in: .capsule
                    )
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedCategory = category
                }
            } label: {
                if isSelected {
                    categoryLabel(category, isSelected: true)
                        .background(Color.indigo.gradient, in: Capsule())
                } else {
                    categoryLabel(category, isSelected: false)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }

    private func categoryLabel(_ category: CastCategory, isSelected: Bool) -> some View {
        Text(category.title(for: language))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, 18)
            .frame(height: 38)
            .contentShape(Capsule())
    }

    private func castRow(_ cast: CastRecord) -> some View {
        HStack(spacing: 8) {
            Button {
                showDetails(for: cast)
            } label: {
                HStack(spacing: 14) {
                    CastArtwork(cast: cast, size: 64)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(cast.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Text(language == .english
                             ? "\(cast.durationMinutes) min Cast"
                             : "\(cast.durationMinutes)分Cast")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(language == .english ? "Open \(cast.title)" : "\(cast.title)の詳細を開く")

            Menu {
                Button {
                    // Favorite persistence will be connected to the Cast API.
                } label: {
                    Label(
                        language == .english ? "Favorite" : "お気に入り",
                        systemImage: "star"
                    )
                }

                Button {
                    // Offline download will be connected to local audio storage.
                } label: {
                    Label(
                        language == .english ? "Download" : "ダウンロード",
                        systemImage: "arrow.down.circle"
                    )
                }

                Button {
                    createShareLink(for: cast)
                } label: {
                    Label(
                        language == .english ? "Share" : "共有",
                        systemImage: "square.and.arrow.up"
                    )
                }

                Divider()

                Button {
                    showDetails(for: cast)
                } label: {
                    Label(
                        language == .english ? "Show Details" : "詳細を表示",
                        systemImage: "info.circle"
                    )
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(language == .english ? "Options for \(cast.title)" : "\(cast.title)のオプション")
        }
        .padding(.vertical, 14)
    }

    private func createShareLink(for cast: CastRecord) {
        Task {
            guard let url = await castStore.createShareURL(
                token: authStore.sessionToken(),
                castID: cast.id
            ) else {
                isErrorPresented = true
                return
            }
            sharePayload = CastSharePayload(url: url)
        }
    }

    private func showDetails(for cast: CastRecord) {
        isDetailPresented = true
        selectedCast = cast
    }

}

private struct CastSharePayload: Identifiable {
    let id = UUID()
    let url: URL
}

private struct SystemShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct CastDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @GestureState private var dragOffset = CGFloat.zero
    @State private var sharePayload: CastSharePayload?
    @State private var isErrorPresented = false
    @State private var isShowingTranscript = false
    @State private var isShowingReportReasons = false
    @State private var isShowingReportSent = false
    @State private var isShowingShareRevoked = false

    let cast: CastRecord
    let authStore: AuthStore
    let castStore: CastStore
    let playbackStore: CastPlaybackStore
    let subscriptionTier: SubscriptionPlanTier
    let language: AppLanguage

    private var isCurrentCast: Bool {
        playbackStore.currentCast?.id == cast.id
    }

    private var isPlaying: Bool {
        isCurrentCast && playbackStore.isPlaying
    }

    private var progress: Double {
        isCurrentCast ? playbackStore.progress : 0
    }

    private var elapsedTime: String {
        isCurrentCast ? playbackStore.elapsedTime : "0:00"
    }

    private var durationTime: String {
        isCurrentCast ? playbackStore.durationTime : "\(cast.durationMinutes):00"
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                Color(red: 0.95, green: 0.95, blue: 0.98)

                Capsule()
                    .fill(.primary.opacity(0.55))
                    .frame(width: 52, height: 6)
                    .padding(.top, proxy.safeAreaInsets.top + 60)
                    .accessibilityHidden(true)

                VStack(spacing: 0) {
                    Spacer(minLength: proxy.safeAreaInsets.top + 68)

                    CastArtwork(cast: cast, size: 280)
                        .offset(y: 78)

                    Spacer(minLength: 32)

                    VStack(alignment: .leading, spacing: 8) {
                        OnePassMarqueeTitle(text: cast.title)

                        HStack(alignment: .center, spacing: 12) {
                            Text(language == .english ? "Cast" : "Cast")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Spacer(minLength: 0)

                            moderationButton
                        }

                        Text(language == .english
                             ? "AI-generated summary; not a verbatim reproduction or a guarantee of factual accuracy."
                             : "AIが生成した要約です。元記事の転載ではなく、内容の正確性を保証するものではありません。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 32)
                    .offset(y: 65)

                    Spacer(minLength: 24)

                    VStack(spacing: 8) {
                        CastSeekBar(progress: progress) { value in
                            playbackStore.seek(toProgress: value, in: cast)
                        }

                        HStack {
                            Text(elapsedTime)
                            Spacer()
                            Text(durationTime)
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                    .offset(y: 25)

                    Spacer(minLength: 30)

                    HStack(spacing: 48) {
                        Button {
                            playbackStore.seek(by: -10, in: cast)
                        } label: {
                            Image(systemName: "gobackward.10")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(language == .english ? "Back 10 seconds" : "10秒戻る")

                        Button {
                            playbackStore.toggle(cast, subscriptionTier: subscriptionTier)
                        } label: {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 44, weight: .bold))
                                .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isPlaying
                                            ? (language == .english ? "Pause" : "一時停止")
                                            : (language == .english ? "Play" : "再生"))

                        Button {
                            playbackStore.seek(by: 10, in: cast)
                        } label: {
                            Image(systemName: "goforward.10")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(language == .english ? "Forward 10 seconds" : "10秒進む")
                    }
                    .offset(y: -7)

                    detailActions
                        .padding(.top, 18)
                        .offset(y: 20)

                    Spacer(minLength: proxy.safeAreaInsets.bottom + 48)
                }
                .padding(.horizontal, 24)
                .allowsHitTesting(!isShowingTranscript)

                if isShowingTranscript {
                    transcriptOverlay(proxy: proxy)
                }

            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: min(max(dragOffset / 4, 0), 30),
                    style: .continuous
                )
            )
            .offset(y: max(dragOffset, 0))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 12)
                    .updating($dragOffset) { value, state, _ in
                        guard abs(value.translation.height) > abs(value.translation.width),
                              value.translation.height > 0 else { return }
                        state = value.translation.height
                    }
                    .onEnded { value in
                        guard value.translation.height > 120 || value.predictedEndTranslation.height > 220 else { return }
                        dismiss()
                    }
            )
            .animation(.spring(response: 0.32, dampingFraction: 0.9), value: dragOffset)
        }
        .ignoresSafeArea()
        .sheet(item: $sharePayload) { payload in
            SystemShareSheet(activityItems: [payload.url])
                .presentationDetents([.medium, .large])
        }
        .appErrorAlert(isPresented: $isErrorPresented, language: language)
        .confirmationDialog(
            language == .english ? "Report this Cast" : "このCastを通報",
            isPresented: $isShowingReportReasons,
            titleVisibility: .visible
        ) {
            reportButton(reason: "inappropriate", title: language == .english ? "Inappropriate content" : "不適切なコンテンツ")
            reportButton(reason: "copyright", title: language == .english ? "Copyright concern" : "著作権に関する問題")
            reportButton(reason: "privacy", title: language == .english ? "Privacy concern" : "プライバシーに関する問題")
            Button(language == .english ? "Cancel" : "キャンセル", role: .cancel) { }
        }
        .alert(language == .english ? "Report sent" : "通報を送信しました", isPresented: $isShowingReportSent) {
            Button(language == .english ? "OK" : "確認", role: .cancel) { }
        } message: {
            Text(language == .english ? "Thank you. We will review this Cast." : "ありがとうございます。内容を確認します。")
        }
        .alert(language == .english ? "Sharing stopped" : "共有を停止しました", isPresented: $isShowingShareRevoked) {
            Button(language == .english ? "OK" : "確認", role: .cancel) { }
        }
    }

    private var detailActions: some View {
        HStack(spacing: 38) {
            transcriptButton
            playbackScreenButton
            shareButton
        }
    }

    private var moderationButton: some View {
        Menu {
            if cast.shareToken != nil {
                Button {
                    isShowingReportReasons = true
                } label: {
                    Label(language == .english ? "Report" : "通報", systemImage: "exclamationmark.bubble")
                }
            }
            if cast.shareToken != nil {
                Button(role: .destructive) {
                    Task {
                        if await castStore.revokeShare(token: authStore.sessionToken(), castID: cast.id) {
                            isShowingShareRevoked = true
                        } else {
                            isErrorPresented = true
                        }
                    }
                } label: {
                    Label(language == .english ? "Stop sharing" : "共有を停止", systemImage: "link.badge.minus")
                }
            }

            Menu {
                ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                    Button {
                        playbackStore.setPlaybackRate(speed)
                    } label: {
                        HStack {
                            Text("\(speed.formatted())x")
                            if playbackStore.playbackRate == speed {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label(language == .english ? "Playback speed" : "再生速度", systemImage: "speedometer")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 24, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(Color.black)
                .frame(width: 46, height: 46)
        }
        .accessibilityLabel(language == .english ? "Cast options" : "Castのオプション")
    }

    private func reportButton(reason: String, title: String) -> some View {
        Button(title) {
            guard let shareToken = cast.shareToken else { return }
            Task {
                if await castStore.reportSharedCast(shareToken: shareToken, reason: reason, details: nil) {
                    isShowingReportSent = true
                } else {
                    isErrorPresented = true
                }
            }
        }
    }

    private var transcriptButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) {
                isShowingTranscript.toggle()
            }
        } label: {
            Image(systemName: "quote.bubble")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(isShowingTranscript ? Color.black : Color.gray)
                .frame(width: 52, height: 52)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(language == .english ? "Transcript" : "文字起こし")
    }

    private var playbackScreenButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) {
                isShowingTranscript = false
            }
        } label: {
            Image(systemName: "waveform")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(isShowingTranscript ? Color.gray : Color.black)
                .frame(width: 52, height: 52)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(language == .english ? "Player" : "再生画面")
    }

    private var shareButton: some View {
        Button {
            createShareLink()
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 52, height: 52)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(language == .english ? "Share" : "共有")
    }

    private func transcriptOverlay(proxy: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: proxy.safeAreaInsets.top + 92)

            HStack {
                Text(language == .english ? "Transcript" : "文字起こし")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)

                Spacer()
            }
            .padding(.bottom, 18)

            ScrollView {
                Text(cast.transcript?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                     ? cast.transcript!
                     : (language == .english ? "Transcript is unavailable." : "文字起こしはありません。"))
                    .font(.system(size: 25.5, design: .rounded))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineSpacing(7)
                    .textSelection(.enabled)
            }
            .scrollIndicators(.hidden)

            Spacer(minLength: 20)

            detailActions
                .padding(.top, 18)
                .offset(y: 3)

            Spacer(minLength: proxy.safeAreaInsets.bottom + 48)
        }
        .padding(.horizontal, 24)
        .frame(width: proxy.size.width, height: proxy.size.height)
        .background(Color(red: 0.95, green: 0.95, blue: 0.98))
    }

    private func createShareLink() {
        Task {
            guard let url = await castStore.createShareURL(
                token: authStore.sessionToken(),
                castID: cast.id
            ) else {
                isErrorPresented = true
                return
            }
            sharePayload = CastSharePayload(url: url)
        }
    }
}

private struct OnePassMarqueeTitle: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var textWidth = CGFloat.zero
    @State private var horizontalOffset = CGFloat.zero

    let text: String

    private let gap = CGFloat(36)
    private let pointsPerSecond = CGFloat(60)

    var body: some View {
        GeometryReader { proxy in
            let availableWidth = max(proxy.size.width, 1)
            let shouldScroll = !reduceMotion && textWidth > availableWidth + 1

            ZStack(alignment: .leading) {
                HStack(spacing: gap) {
                    titleText

                    if shouldScroll {
                        titleText
                            .accessibilityHidden(true)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
                .offset(x: horizontalOffset)
            }
            .frame(width: availableWidth, height: 42, alignment: .leading)
            .clipped()
            .task(id: "\(text)|\(Int(availableWidth.rounded()))|\(Int(textWidth.rounded()))|\(reduceMotion)") {
                withAnimation(.none) {
                    horizontalOffset = 0
                }
                guard shouldScroll else { return }

                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }

                let travelDistance = textWidth + gap
                let duration = Double(travelDistance / pointsPerSecond)
                withAnimation(.linear(duration: duration)) {
                    horizontalOffset = -travelDistance
                }
            }
        }
        .frame(height: 42)
        .background(alignment: .leading) {
            titleText
                .fixedSize(horizontal: true, vertical: false)
                .hidden()
                .onGeometryChange(for: CGFloat.self) { geometry in
                    geometry.size.width
                } action: { width in
                    textWidth = width
                }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }

    private var titleText: some View {
        Text(text)
            .font(.title.weight(.bold))
            .foregroundStyle(.primary)
            .lineLimit(1)
    }
}

private struct CastSeekBar: View {
    let progress: Double
    let onChanged: (Double) -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let clampedProgress = min(max(progress, 0), 1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.primary.opacity(0.18))
                    .frame(height: 12)

                Capsule()
                    .fill(.primary)
                    .frame(width: width * clampedProgress, height: 12)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onChanged(min(max(value.location.x / width, 0), 1))
                    }
            )
        }
        .frame(height: 28)
        .accessibilityElement()
        .accessibilityLabel("再生位置")
        .accessibilityValue("\(Int(progress * 100))%")
    }
}

private struct CastArtwork: View {
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

#Preview {
    PlayerView(authStore: AuthStore(), castStore: CastStore(), playbackStore: CastPlaybackStore(), subscriptionTier: .plus, selectedCast: .constant(nil), isDetailPresented: .constant(false))
}
