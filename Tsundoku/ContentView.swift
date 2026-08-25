//
//  ContentView.swift
//  Tsundoku
//
//  Created by 大石　凌央 on 2026/08/05.
//

import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppLanguage.storageKey) private var appLanguage = AppLanguage.japanese.rawValue
    @AppStorage(AppAppearance.storageKey) private var appAppearance = AppAppearance.system.rawValue
    @State private var isShowingLaunchSplash = true
    @State private var isAuthenticationPresented = false
    @State private var isShowingSocialProfileSetup = false
    @State private var authenticationMode: AuthenticationMode = .signup
    @State private var selectedTab: AppTab = .home
    @State private var articleLibrary = ArticleLibrary()
    @State private var authStore = AuthStore()
    @State private var subscriptionStore = SubscriptionStore()
    @State private var castStore = CastStore()
    @State private var playbackStore = CastPlaybackStore.shared
    @State private var networkStatus = NetworkStatusMonitor()
    @State private var isShowingSubscription = false
    @State private var isDeepLinkErrorPresented = false
    @State private var isCastDetailPresented = false
    @State private var selectedCast: CastRecord?
    @State private var tabAccountAvatar: UIImage?

    var body: some View {
        Group {
            if isShowingLaunchSplash {
                LaunchSplashView()
            } else if case .signedIn = authStore.status {
                mainTabView
                    .offlineWarning(language: currentLanguage, isOffline: !networkStatus.isConnected)
            } else if case .checking = authStore.status {
                ProgressView()
            } else {
                registrationFlow
            }
        }
        .environment(\.locale, Locale(identifier: currentLanguage == .english ? "en" : "ja"))
        .preferredColorScheme(AppAppearance(rawValue: appAppearance)?.colorScheme)
        .onOpenURL { url in
            handleIncomingURL(url)
        }
        .appErrorAlert(isPresented: $isDeepLinkErrorPresented, language: currentLanguage)
        .fullScreenCover(isPresented: $isShowingSocialProfileSetup) {
            SocialProfileSetupView(authStore: authStore, language: currentLanguage)
        }
        .sheet(isPresented: $isShowingSubscription) {
            NavigationStack {
                SubscriptionManagementView(
                    subscriptionStore: subscriptionStore,
                    language: currentLanguage,
                    initialTier: .plus
                )
            }
        }
        .task {
            await prepareForLaunch()
        }
        .task(id: signedInUserID) {
            if let signedInUserID {
                // Prevent the previous account's Cast list from being visible
                // while the new account's server-backed list is loading.
                castStore.clear()
                await subscriptionStore.identify(
                    userID: signedInUserID,
                    sessionToken: authStore.sessionToken()
                )
                await castStore.load(token: authStore.sessionToken())
                PushDeviceTokenRegistration.shared.registerIfPossible(sessionToken: authStore.sessionToken())
                articleLibrary.setServerSyncToken(authStore.sessionToken())
                await articleLibrary.syncIfNeeded(
                    token: authStore.sessionToken(),
                    userID: signedInUserID
                )
            } else if case .signedOut = authStore.status {
                await subscriptionStore.signOut()
                castStore.clear()
                articleLibrary.resetServerSync()
            }
        }
        .task(id: signedInProfileImageURL) {
            tabAccountAvatar = await loadCircularTabAvatar(from: signedInProfileImageURL)
        }
        .onChange(of: authStore.status) { _, status in
            guard case .signedIn(let user) = status,
                  user.preferredLanguage == AppLanguage.japanese.rawValue ||
                    user.preferredLanguage == AppLanguage.english.rawValue else { return }
            appLanguage = user.preferredLanguage
        }
        .onChange(of: appLanguage) { _, language in
            guard case .signedIn(let user) = authStore.status,
                  user.preferredLanguage != language else { return }
            Task {
                try? await authStore.updatePreferredLanguage(language)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            playbackStore.handleScenePhase(phase, subscriptionTier: subscriptionStore.planTier)
            guard phase == .active, signedInUserID != nil else { return }
            Task {
                await subscriptionStore.refresh()
                await castStore.load(token: authStore.sessionToken())
            }
        }
    }

    private var currentLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguage) ?? .japanese
    }

    private var signedInUserID: String? {
        guard case .signedIn(let user) = authStore.status else { return nil }
        return user.id
    }

    private var signedInProfileImageURL: URL? {
        guard case .signedIn(let user) = authStore.status else { return nil }
        return user.profileImageURL
    }

    private var unreadArticleCount: Int {
        articleLibrary.articles
            .map { $0.displayArticle(language: currentLanguage) }
            .filter { $0.status == .unread }
            .count
    }

    private func prepareForLaunch() async {
        let clock = ContinuousClock()
        let startedAt = clock.now

        await authStore.restoreSession()

        let minimumDuration = Duration.milliseconds(1_500)
        let elapsed = startedAt.duration(to: clock.now)
        if elapsed < minimumDuration {
            try? await Task.sleep(for: minimumDuration - elapsed)
        }

        guard !Task.isCancelled else { return }
        isShowingLaunchSplash = false
    }

    @ViewBuilder
    private var registrationFlow: some View {
        Group {
            if currentLanguage == .english {
                OnboardingViewEN(onFinish: presentAuthentication)
            } else {
                OnboardingView(onFinish: presentAuthentication)
            }
        }
        .sheet(isPresented: $isAuthenticationPresented) {
            authenticationView
                // 認証内容に合わせてシートをコンパクトにし、下側の余白を抑えます。
                // 入力中は内部の ScrollView がキーボードに合わせてスクロールします。
                .presentationDetents([.height(authenticationSheetHeight)])
                .presentationDragIndicator(.hidden)
                .interactiveDismissDisabled()
        }
    }

    @ViewBuilder
    private var authenticationView: some View {
        switch authenticationMode {
        case .signup:
            if currentLanguage == .english {
                SignupViewEN(authStore: authStore, onBack: dismissAuthentication, onComplete: completeRegistration, onShowLogin: showLogin)
            } else {
                SignupView(authStore: authStore, onBack: dismissAuthentication, onComplete: completeRegistration, onShowLogin: showLogin)
            }
        case .login:
            if currentLanguage == .english {
                LoginViewEN(authStore: authStore, onBack: dismissAuthentication, onComplete: completeRegistration, onShowSignup: showSignup)
            } else {
                LoginView(authStore: authStore, onBack: dismissAuthentication, onComplete: completeRegistration, onShowSignup: showSignup)
            }
        }
    }

    private var authenticationSheetHeight: CGFloat {
        // 下側だけを詰めるため、上側のタブ位置は維持したまま高さを調整します。
        // 目安: 1mm ≒ 4pt
        authenticationMode == .login ? 536 : 492
    }

    private var mainTabView: some View {
        ZStack(alignment: .bottom) {
            mainTabViewContent

            if let currentCast = playbackStore.currentCast,
               playbackStore.hasStartedPlayback,
               !isCastDetailPresented,
               selectedTab != .settings {
                miniPlayerOverlay(for: currentCast)
                    .transition(.opacity)
            }
        }
        .animation(.snappy, value: playbackStore.hasStartedPlayback)
        .animation(.snappy, value: isCastDetailPresented)
        .animation(.easeInOut(duration: 0.24), value: selectedTab == .settings)
    }

    @ViewBuilder
    private func miniPlayerOverlay(for cast: CastRecord) -> some View {
        let content = DigestTabAccessory(
            language: currentLanguage,
            cast: cast,
            playbackStore: playbackStore,
            subscriptionTier: subscriptionStore.planTier,
            openPlayer: { openCastDetails(cast) },
            close: { playbackStore.stop() }
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 6)

        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: .capsule)
                .padding(.horizontal, 20)
                .padding(.bottom, 72)
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.horizontal, 20)
                .padding(.bottom, 72)
        }
    }

    private var mainTabViewContent: some View {
        TabView(selection: $selectedTab) {
            Tab(value: .home) {
                if currentLanguage == .english {
                    HomeViewEN(authStore: authStore, articleLibrary: articleLibrary, subscriptionStore: subscriptionStore)
                } else {
                    HomeView(authStore: authStore, articleLibrary: articleLibrary, subscriptionStore: subscriptionStore)
                }
            } label: {
                Image(systemName: "house")
                    .accessibilityLabel(currentLanguage == .english ? "Home" : "ホーム")
            }

            Tab(value: .stock) {
                if currentLanguage == .english {
                    StockViewEN(articleLibrary: articleLibrary, subscriptionStore: subscriptionStore, castStore: castStore, authStore: authStore)
                } else {
                    StockView(articleLibrary: articleLibrary, subscriptionStore: subscriptionStore, castStore: castStore, authStore: authStore)
                }
            } label: {
                Image(systemName: "tray.full")
                    .accessibilityLabel(currentLanguage == .english ? "Stock" : "ストック")
            }
            .badge(unreadArticleCount)

            Tab(value: .player) {
                if currentLanguage == .english {
                    PlayerViewEN(authStore: authStore, castStore: castStore, playbackStore: playbackStore, subscriptionTier: subscriptionStore.planTier, selectedCast: $selectedCast, isDetailPresented: $isCastDetailPresented)
                } else {
                    PlayerView(authStore: authStore, castStore: castStore, playbackStore: playbackStore, subscriptionTier: subscriptionStore.planTier, selectedCast: $selectedCast, isDetailPresented: $isCastDetailPresented)
                }
            } label: {
                Image(systemName: "headphones")
                    .accessibilityLabel(currentLanguage == .english ? "Podcast" : "ポッドキャスト")
            }

            Tab(value: .settings) {
                AccountView(
                    authStore: authStore,
                    subscriptionStore: subscriptionStore,
                    articleLibrary: articleLibrary,
                    castStore: castStore,
                    playbackStore: playbackStore,
                    language: currentLanguage,
                    openSavedArticles: {
                        Task { @MainActor in
                            selectedTab = .stock
                        }
                    },
                    openCastLibrary: { category in
                        UserDefaults.standard.set(category, forKey: "castLibrarySelectedCategory")
                        Task { @MainActor in
                            selectedTab = .player
                        }
                    }
                )
            } label: {
                if let tabAccountAvatar {
                    Image(uiImage: tabAccountAvatar)
                        .renderingMode(.original)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .accessibilityLabel(currentLanguage == .english ? "Account" : "アカウント")
                } else {
                    Image(systemName: "person.crop.circle")
                        .accessibilityLabel(currentLanguage == .english ? "Account" : "アカウント")
                }
            }
        }
        .tabBarMinimizeBehavior(selectedTab == .player ? .onScrollDown : .never)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                articleLibrary.refresh()
            }
        }
    }

    private func presentAuthentication() {
        authenticationMode = .signup
        isAuthenticationPresented = true
    }

    private func showLogin() {
        authenticationMode = .login
    }

    private func showSignup() {
        authenticationMode = .signup
    }

    private func dismissAuthentication() {
        isAuthenticationPresented = false
    }

    private func completeRegistration() {
        isAuthenticationPresented = false
        authenticationMode = .signup
        guard authStore.requiresSocialProfileSetup else { return }
        DispatchQueue.main.async {
            isShowingSocialProfileSetup = true
        }
    }

    private func handleIncomingURL(_ url: URL) {
        if url.scheme == "stashcast" {
            if url.host == "playback" {
                handlePlaybackCommand(url)
                return
            }

            switch url.host {
            case "subscription":
                isShowingSubscription = true
            case "stock":
                selectedTab = .stock
                articleLibrary.refresh()
            case "player":
                selectedTab = .player
            case "cast":
                guard let token = url.pathComponents.dropFirst().first else { return }
                openSharedCast(token: token)
            default:
                break
            }
            return
        }

        guard url.scheme == "https",
              url.host == "stash-cast.vercel.app",
              url.pathComponents.count >= 3,
              url.pathComponents[1] == "c" else { return }
        openSharedCast(token: url.pathComponents[2])
    }

    private func handlePlaybackCommand(_ url: URL) {
        switch url.path {
        case "/toggle":
            playbackStore.toggleCurrent(subscriptionTier: subscriptionStore.planTier)
        case "/seek":
            guard let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "seconds" })?
                .value,
                  let seconds = Double(value) else { return }
            playbackStore.seekCurrent(by: seconds)
        default:
            break
        }
    }

    private func openSharedCast(token: String) {
        selectedTab = .player
        Task {
            if !(await castStore.openSharedCast(shareToken: token)) {
                isDeepLinkErrorPresented = true
            }
        }
    }

    private func openCastDetails(_ cast: CastRecord) {
        selectedTab = .player
        isCastDetailPresented = true
        selectedCast = cast
    }

    private func loadCircularTabAvatar(from url: URL?) async -> UIImage? {
        guard let url else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode),
                  let image = UIImage(data: data) else { return nil }
            return circularTabAvatar(from: image)
        } catch {
            return nil
        }
    }

    private func circularTabAvatar(from image: UIImage) -> UIImage {
        let size = CGSize(width: 28, height: 28)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = false

        let avatar = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let outputRect = CGRect(origin: .zero, size: size)
            UIBezierPath(ovalIn: outputRect).addClip()

            let scale = max(size.width / image.size.width, size.height / image.size.height)
            let drawSize = CGSize(
                width: image.size.width * scale,
                height: image.size.height * scale
            )
            let drawRect = CGRect(
                x: (size.width - drawSize.width) / 2,
                y: (size.height - drawSize.height) / 2,
                width: drawSize.width,
                height: drawSize.height
            )
            image.draw(in: drawRect)
        }
        return avatar.withRenderingMode(.alwaysOriginal)
    }
}

private enum AuthenticationMode {
    case signup
    case login
}

private struct LaunchSplashView: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color("LaunchBackgroundLight")

                Image("LaunchLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: min(proxy.size.width * 0.86, 360))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

private enum AppTab: Hashable {
    case home
    case stock
    case player
    case settings
}

private struct UIKitCardPresenter<Content: View>: UIViewControllerRepresentable {
    @Binding private var isPresented: Bool
    private let content: () -> Content

    init(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        _isPresented = isPresented
        self.content = content
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> CardPresentationAnchorViewController {
        let viewController = CardPresentationAnchorViewController()
        viewController.onViewDidAppear = { [weak coordinator = context.coordinator] in
            coordinator?.updatePresentation()
        }
        context.coordinator.anchorViewController = viewController
        return viewController
    }

    func updateUIViewController(
        _ uiViewController: CardPresentationAnchorViewController,
        context: Context
    ) {
        context.coordinator.parent = self
        context.coordinator.anchorViewController = uiViewController
        context.coordinator.updatePresentation()
    }

    static func dismantleUIViewController(
        _ uiViewController: CardPresentationAnchorViewController,
        coordinator: Coordinator
    ) {
        coordinator.dismissCard(animated: false)
    }

    final class Coordinator: NSObject,
        UIViewControllerTransitioningDelegate,
        UIAdaptivePresentationControllerDelegate {
        var parent: UIKitCardPresenter
        weak var anchorViewController: CardPresentationAnchorViewController?

        private var hostingController: UIHostingController<Content>?
        private var isTransitioning = false

        init(parent: UIKitCardPresenter) {
            self.parent = parent
        }

        func updatePresentation() {
            guard let anchorViewController,
                  anchorViewController.viewIfLoaded?.window != nil else {
                return
            }

            if parent.isPresented {
                if let hostingController {
                    hostingController.rootView = parent.content()
                } else {
                    presentCard(from: anchorViewController)
                }
            } else {
                dismissCard(animated: true)
            }
        }

        func dismissCard(animated: Bool) {
            guard hostingController != nil, !isTransitioning else { return }
            isTransitioning = true

            anchorViewController?.dismiss(animated: animated) { [weak self] in
                self?.hostingController = nil
                self?.isTransitioning = false
            }
        }

        private func presentCard(from anchorViewController: UIViewController) {
            guard !isTransitioning else { return }

            let hostingController = UIHostingController(rootView: parent.content())
            hostingController.view.backgroundColor = .systemBackground
            hostingController.modalPresentationStyle = .custom
            hostingController.isModalInPresentation = true
            hostingController.transitioningDelegate = self
            self.hostingController = hostingController
            isTransitioning = true

            anchorViewController.present(hostingController, animated: true) { [weak self] in
                self?.isTransitioning = false
            }
        }

        func presentationController(
            forPresented presented: UIViewController,
            presenting: UIViewController?,
            source: UIViewController
        ) -> UIPresentationController? {
            let presentationController = AuthenticationCardPresentationController(
                presentedViewController: presented,
                presenting: presenting
            )
            presentationController.delegate = self
            presentationController.onDismiss = { [weak self] in
                guard let self else { return }
                hostingController = nil
                isTransitioning = false
                parent.isPresented = false
            }
            return presentationController
        }

        func presentationControllerShouldDismiss(
            _ presentationController: UIPresentationController
        ) -> Bool {
            false
        }

        func animationController(
            forPresented presented: UIViewController,
            presenting: UIViewController,
            source: UIViewController
        ) -> UIViewControllerAnimatedTransitioning? {
            AuthenticationCardAnimator(isPresenting: true)
        }

        func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
            AuthenticationCardAnimator(isPresenting: false)
        }
    }
}

private final class CardPresentationAnchorViewController: UIViewController {
    var onViewDidAppear: (() -> Void)?

    override func loadView() {
        let view = UIView()
        view.backgroundColor = .clear
        self.view = view
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        onViewDidAppear?()
    }
}

private final class AuthenticationCardPresentationController: UIPresentationController {
    var onDismiss: (() -> Void)?

    private let dimmingView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.36)
        view.alpha = 0
        return view
    }()

    override var frameOfPresentedViewInContainerView: CGRect {
        guard let containerView else { return .zero }

        let bounds = containerView.bounds
        let width = min(bounds.width - 32, 520)
        let bottomExtension: CGFloat = 12
        let topReduction: CGFloat = 100
        let height = bounds.height * 0.64 + bottomExtension - topReduction
        let bottomSpacing = max(containerView.safeAreaInsets.bottom + 8, 16) - bottomExtension

        return CGRect(
            x: bounds.midX - width / 2,
            y: bounds.maxY - bottomSpacing - height,
            width: width,
            height: height
        )
    }

    override func presentationTransitionWillBegin() {
        guard let containerView else { return }

        dimmingView.frame = containerView.bounds
        containerView.insertSubview(dimmingView, at: 0)

        presentedViewController.transitionCoordinator?.animate { [weak self] _ in
            self?.dimmingView.alpha = 1
        }
    }

    override func dismissalTransitionWillBegin() {
        presentedViewController.transitionCoordinator?.animate { [weak self] _ in
            self?.dimmingView.alpha = 0
        }
    }

    override func dismissalTransitionDidEnd(_ completed: Bool) {
        guard completed else { return }
        dimmingView.removeFromSuperview()
        onDismiss?()
    }

    override func containerViewWillLayoutSubviews() {
        super.containerViewWillLayoutSubviews()
        dimmingView.frame = containerView?.bounds ?? .zero
        presentedView?.frame = frameOfPresentedViewInContainerView
        presentedView?.layer.cornerRadius = 28
        presentedView?.layer.cornerCurve = .continuous
        presentedView?.clipsToBounds = true
    }
}

private final class AuthenticationCardAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    private let isPresenting: Bool

    init(isPresenting: Bool) {
        self.isPresenting = isPresenting
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        isPresenting ? 0.48 : 0.28
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        if isPresenting {
            animatePresentation(using: transitionContext)
        } else {
            animateDismissal(using: transitionContext)
        }
    }

    private func animatePresentation(using transitionContext: UIViewControllerContextTransitioning) {
        guard let viewController = transitionContext.viewController(forKey: .to),
              let presentedView = transitionContext.view(forKey: .to) else {
            transitionContext.completeTransition(false)
            return
        }

        let containerView = transitionContext.containerView
        presentedView.frame = transitionContext.finalFrame(for: viewController)
        presentedView.transform = CGAffineTransform(
            translationX: 0,
            y: containerView.bounds.maxY - presentedView.frame.minY + 24
        )
        containerView.addSubview(presentedView)

        UIView.animate(
            withDuration: transitionDuration(using: transitionContext),
            delay: 0,
            usingSpringWithDamping: 0.86,
            initialSpringVelocity: 0.55,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            presentedView.transform = .identity
        } completion: { finished in
            transitionContext.completeTransition(finished && !transitionContext.transitionWasCancelled)
        }
    }

    private func animateDismissal(using transitionContext: UIViewControllerContextTransitioning) {
        guard let presentedView = transitionContext.view(forKey: .from) else {
            transitionContext.completeTransition(false)
            return
        }

        let containerView = transitionContext.containerView

        UIView.animate(
            withDuration: transitionDuration(using: transitionContext),
            delay: 0,
            options: [.curveEaseIn, .allowUserInteraction]
        ) {
            presentedView.transform = CGAffineTransform(
                translationX: 0,
                y: containerView.bounds.maxY - presentedView.frame.minY + 24
            )
        } completion: { finished in
            let completed = finished && !transitionContext.transitionWasCancelled
            if completed {
                presentedView.removeFromSuperview()
            }
            transitionContext.completeTransition(completed)
        }
    }
}

#Preview {
    ContentView()
}
