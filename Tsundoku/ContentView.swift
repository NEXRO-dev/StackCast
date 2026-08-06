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
    @State private var isShowingLaunchSplash = true
    @State private var isAuthenticationPresented = false
    @State private var selectedTab: AppTab = .home
    @State private var articleLibrary = ArticleLibrary()
    @State private var authStore = AuthStore()

    var body: some View {
        Group {
            if isShowingLaunchSplash {
                LaunchSplashView()
            } else if case .signedIn = authStore.status {
                mainTabView
            } else if case .checking = authStore.status {
                ProgressView()
            } else {
                registrationFlow
            }
        }
        .environment(\.locale, Locale(identifier: currentLanguage == .english ? "en" : "ja"))
        .task {
            await prepareForLaunch()
        }
    }

    private var currentLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguage) ?? .japanese
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
        .background {
            UIKitCardPresenter(isPresented: $isAuthenticationPresented) {
                authenticationView
            }
        }
    }

    @ViewBuilder
    private var authenticationView: some View {
        if currentLanguage == .english {
            SignupViewEN(
                authStore: authStore,
                onBack: dismissAuthentication,
                onComplete: completeRegistration
            )
        } else {
            SignupView(
                authStore: authStore,
                onBack: dismissAuthentication,
                onComplete: completeRegistration
            )
        }
    }

    private var mainTabView: some View {
        TabView(selection: $selectedTab) {
            Tab(value: .home) {
                if currentLanguage == .english {
                    HomeViewEN(articleLibrary: articleLibrary)
                } else {
                    HomeView(articleLibrary: articleLibrary)
                }
            } label: {
                Image(systemName: "house")
                    .accessibilityLabel(currentLanguage == .english ? "Home" : "ホーム")
            }

            Tab(value: .stock) {
                if currentLanguage == .english {
                    StockViewEN(articleLibrary: articleLibrary)
                } else {
                    StockView(articleLibrary: articleLibrary)
                }
            } label: {
                Image(systemName: "tray.full")
                    .accessibilityLabel(currentLanguage == .english ? "Stock" : "ストック")
            }
            .badge(unreadArticleCount)

            Tab(value: .player) {
                if currentLanguage == .english {
                    PlayerViewEN()
                } else {
                    PlayerView()
                }
            } label: {
                Image(systemName: "play.circle")
                    .accessibilityLabel(currentLanguage == .english ? "Player" : "プレイヤー")
            }

            Tab(value: .log) {
                if currentLanguage == .english {
                    LogViewEN(articleLibrary: articleLibrary)
                } else {
                    LogView(articleLibrary: articleLibrary)
                }
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .accessibilityLabel(currentLanguage == .english ? "Log" : "ログ")
            }

            Tab(value: .settings) {
                if currentLanguage == .english {
                    SettingsViewEN(authStore: authStore)
                } else {
                    SettingsView(authStore: authStore)
                }
            } label: {
                Image(systemName: "gearshape")
                    .accessibilityLabel(currentLanguage == .english ? "Settings" : "設定")
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
        isAuthenticationPresented = true
    }

    private func dismissAuthentication() {
        isAuthenticationPresented = false
    }

    private func completeRegistration() {
        isAuthenticationPresented = false
    }
}

private struct LaunchSplashView: View {
    var body: some View {
        Color("LaunchBackground")
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

private enum AppTab: Hashable {
    case home
    case stock
    case player
    case log
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
