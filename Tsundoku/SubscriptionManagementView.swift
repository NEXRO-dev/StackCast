//
//  SubscriptionManagementView.swift
//  Tsundoku
//

import SwiftUI
import RevenueCat

struct SubscriptionManagementView: View {
    let subscriptionStore: SubscriptionStore
    let language: AppLanguage
    private let loadsSubscriptionData: Bool
    private let showsUpgradeHeader: Bool
    private let termsURL = URL(string: "https://stackcast.app/terms")!
    private let privacyURL = URL(string: "https://stackcast.app/privacy")!

    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedBillingPeriod: SubscriptionBillingPeriod = .monthly
    @State private var selectedTier: SubscriptionTier = .pro
    @State private var hasLoadedSubscriptionState = false
    @State private var isShowingPlanChangeAlert = false
    @State private var browserDestination: InAppBrowserDestination?

    private var copy: SubscriptionCopy {
        SubscriptionCopy(language: language)
    }

    private var subscriptionErrorBinding: Binding<Bool> {
        Binding(
            get: { subscriptionStore.errorMessage != nil },
            set: { if !$0 { subscriptionStore.clearError() } }
        )
    }

    init(
        subscriptionStore: SubscriptionStore,
        language: AppLanguage,
        loadsSubscriptionData: Bool = true,
        initialTier: SubscriptionTier = .pro,
        showsUpgradeHeader: Bool = true
    ) {
        self.subscriptionStore = subscriptionStore
        self.language = language
        self.loadsSubscriptionData = loadsSubscriptionData
        self.showsUpgradeHeader = showsUpgradeHeader
        _selectedTier = State(initialValue: initialTier)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if showsUpgradeHeader {
                    planIntro
                }
                billingPeriodSwitcher
                tierCards
                billingDisclosure
                supportSection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(copy.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                subscriptionActionsMenu
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            purchaseArea
        }
        .onChange(of: selectedBillingPeriod) { _, period in
            selectedTier = period == .lifetime ? .lifetime : .pro
        }
        .onChange(of: subscriptionStore.activeProductIdentifier) { oldIdentifier, newIdentifier in
            selectedTier = currentTier

            guard hasLoadedSubscriptionState,
                  oldIdentifier != newIdentifier else { return }

            isShowingPlanChangeAlert = true
        }
        .alert(copy.planChangedTitle, isPresented: $isShowingPlanChangeAlert) {
            Button(copy.planChangeDismiss, role: .cancel) { }
        } message: {
            Text(copy.planChangedMessage(planName: currentTier.title(copy: copy)))
        }
        .appErrorAlert(
            isPresented: subscriptionErrorBinding,
            language: language,
            onDismiss: subscriptionStore.clearError
        )
        .sheet(item: $browserDestination) { destination in
            InAppBrowserView(url: destination.url)
        }
        .task {
            guard loadsSubscriptionData else { return }
            await subscriptionStore.refresh()
            hasLoadedSubscriptionState = true
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, loadsSubscriptionData, hasLoadedSubscriptionState else { return }
            Task {
                await subscriptionStore.refresh()
            }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(subscriptionStore.isPro ? Color.indigo.opacity(0.15) : Color.secondary.opacity(0.12))
                    Image(systemName: subscriptionStore.isPro ? "checkmark.seal.fill" : "sparkles")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(subscriptionStore.isPro ? .indigo : .secondary)
                }
                .frame(width: 58, height: 58)

                VStack(alignment: .leading, spacing: 4) {
                    Text(copy.proPlan)
                        .font(.title3.bold())
                    Text(copy.proDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            if subscriptionStore.isPro {
                Divider()

                VStack(spacing: 12) {
                    subscriptionDetail(
                        title: copy.plan,
                        value: subscriptionStore.activeProductIdentifier ?? copy.proPlan,
                        symbol: "calendar"
                    )

                    if let expirationDate = subscriptionStore.expirationDate {
                        subscriptionDetail(
                            title: subscriptionStore.willRenew ? copy.renewalDate : copy.endsOn,
                            value: expirationDate.formatted(date: .abbreviated, time: .omitted),
                            symbol: subscriptionStore.willRenew ? "arrow.triangle.2.circlepath" : "calendar.badge.exclamationmark"
                        )
                    }

                    if subscriptionStore.hasBillingIssue {
                        Label(copy.billingIssue, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(20)
        .background(Color.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.indigo.opacity(0.2), lineWidth: 1)
        }
    }

    private var billingPeriodSwitcher: some View {
        Picker(copy.choosePlan, selection: $selectedBillingPeriod) {
            ForEach(SubscriptionBillingPeriod.allCases) { period in
                Text(period.title(copy: copy)).tag(period)
            }
        }
        .pickerStyle(.segmented)
    }

    private var planIntro: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 8) {
                Text(copy.upgradeTitle)
                    .font(.title.bold())

                Text(copy.upgradeMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 30, height: 30)
                    .modifier(CloseButtonGlassBackground())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(language == .english ? "Close" : "閉じる")
        }
        .padding(.vertical, 4)
    }

    private var tierCards: some View {
        VStack(spacing: 12) {
            ForEach(displayedTiers) { tier in
                tierCard(tier)
            }
        }
    }

    private var currentTier: SubscriptionTier {
        switch subscriptionStore.planTier {
        case .free: return .free
        case .plus: return .plus
        case .pro: return .pro
        case .lifetime: return .lifetime
        }
    }

    private var purchasedTier: SubscriptionTier {
        switch subscriptionStore.activeBillingPlanTier {
        case .free: return .free
        case .plus: return .plus
        case .pro: return .pro
        case .lifetime: return .lifetime
        }
    }

    private var displayedTiers: [SubscriptionTier] {
        var tiers: [SubscriptionTier]

        if selectedBillingPeriod == .lifetime {
            tiers = [.free, .lifetime]
        } else {
            tiers = [.free, .plus, .pro]
        }

        if currentTier != .free, !tiers.contains(currentTier) {
            tiers.insert(currentTier, at: 0)
        }

        return tiers
    }

    private func tierCard(_ tier: SubscriptionTier) -> some View {
        let package = package(for: tier, period: selectedBillingPeriod)
        let isSelected = tier == selectedTier

        return Button {
            guard tier != .free,
                  currentTier == .free || purchasedTier != tier else { return }
            selectedTier = tier
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(tier.title(copy: copy))
                                .font(.headline.bold())

                            if currentTier == tier {
                                Text(copy.currentPlan)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.indigo)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Color.indigo.opacity(0.12), in: Capsule())
                            }
                        }
                        Text(tier.subtitle(copy: copy))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 12)

                    Text(priceText(for: tier, package: package, period: selectedBillingPeriod))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.indigo)
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(tier.features(copy: copy, period: selectedBillingPeriod), id: \.self) { feature in
                        Label(feature, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.indigo)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(isSelected ? Color.indigo : Color.indigo.opacity(0.14), lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func package(for tier: SubscriptionTier, period: SubscriptionBillingPeriod) -> Package? {
        let periodPackages = subscriptionStore.offering?.availablePackages.filter { package in
            let identifiers = "\(package.identifier) \(package.storeProduct.productIdentifier)".lowercased()
            return period.matches(package: package, identifiers: identifiers)
        }

        if tier == .lifetime {
            return periodPackages?.first
        }

        return periodPackages?.first { package in
            let identifiers = "\(package.identifier) \(package.storeProduct.productIdentifier)".lowercased()
            return identifiers.contains(tier.rawValue)
        }
    }

    private func priceText(for tier: SubscriptionTier, package: Package?, period: SubscriptionBillingPeriod) -> String {
        if tier == .free {
            return copy.freePrice
        }

        guard let package else { return copy.unavailable }
        return "\(package.storeProduct.localizedPriceString)\(period.priceSuffix(copy: copy))"
    }

    private var supportSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 18) {
                Button {
                    browserDestination = InAppBrowserDestination(url: termsURL)
                } label: {
                    Label(copy.termsOfUse, systemImage: "doc.text")
                }

                Button {
                    browserDestination = InAppBrowserDestination(url: privacyURL)
                } label: {
                    Label(copy.privacyPolicy, systemImage: "hand.raised")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private var billingDisclosure: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(copy.billingDisclosureTitle, systemImage: "creditcard")
                .font(.subheadline.weight(.semibold))
            Text(copy.billingDisclosure)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var subscriptionActionsMenu: some View {
        Menu {
            if subscriptionStore.hasActiveStoreSubscription,
               let managementURL = subscriptionStore.subscriptionManagementURL {
                Button {
                    openURL(managementURL)
                } label: {
                    Label(copy.manageSubscription, systemImage: "arrow.up.forward.app")
                }
            }

            Button {
                Task { await subscriptionStore.restorePurchases() }
            } label: {
                Label(copy.restorePurchases, systemImage: "arrow.clockwise")
            }
            .disabled(subscriptionStore.isLoading)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 36, height: 36)
                .contentShape(Circle())
                .modifier(SubscriptionMenuGlassModifier())
        }
        .accessibilityLabel(copy.moreActions)
    }

    @ViewBuilder
    private var purchaseArea: some View {
        if selectedTier != .free
            && (currentTier == .free || selectedTier != purchasedTier) {
            VStack(spacing: 10) {
                if selectedBillingPeriod != .lifetime {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(.indigo)
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(copy.autoRenewalTitle)
                                .font(.subheadline.weight(.semibold))
                            Text(copy.autoRenewalNotice)
                            Text(copy.purchaseFootnote)
                                .foregroundStyle(.secondary)
                        }
                        .font(.footnote)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(.indigo)
                            .padding(.top, 2)
                        Text(copy.lifetimePurchaseNotice)
                            .font(.footnote)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                if let package = package(for: selectedTier, period: selectedBillingPeriod) {
                    Button {
                        Task { await subscriptionStore.purchase(package: package) }
                    } label: {
                        Group {
                            if subscriptionStore.isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Text(copy.startPro(tier: selectedTier, period: selectedBillingPeriod, price: package.storeProduct.localizedPriceString))
                            }
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                    .disabled(subscriptionStore.isLoading)
                } else if subscriptionStore.isLoading {
                    ProgressView(copy.loadingPlans)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                } else {
                    Text(selectedTier.unavailableMessage(period: selectedBillingPeriod, copy: copy))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }

            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(.bar)
        }
    }

    private func subscriptionDetail(title: String, value: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.indigo)
                .frame(width: 20)
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

}

private enum SubscriptionBillingPeriod: String, CaseIterable, Identifiable {
    case monthly
    case yearly
    case lifetime

    // 買い切りプランを再開するときは、ここに `.lifetime` を戻します。
    static var allCases: [SubscriptionBillingPeriod] {
        [.monthly, .yearly /*, .lifetime*/]
    }

    var id: Self { self }

    fileprivate func title(copy: SubscriptionCopy) -> String {
        switch self {
        case .monthly: copy.monthlyPlan
        case .yearly: copy.yearlyPlan
        case .lifetime: copy.lifetimePlan
        }
    }

    func matches(package: Package, identifiers: String) -> Bool {
        switch self {
        case .monthly:
            package.packageType == .monthly || identifiers.contains("monthly") || identifiers.contains("month")
        case .yearly:
            package.packageType == .annual || identifiers.contains("annual") || identifiers.contains("yearly") || identifiers.contains("year")
        case .lifetime:
            package.packageType == .lifetime || identifiers.contains("lifetime") || identifiers.contains("one-time") || identifiers.contains("onetime")
        }
    }

    func priceSuffix(copy: SubscriptionCopy) -> String {
        switch self {
        case .monthly: "/\(copy.month)"
        case .yearly: "/\(copy.year)"
        case .lifetime: ""
        }
    }
}

enum SubscriptionTier: String, CaseIterable, Identifiable {
    case free
    case plus
    case pro
    case lifetime

    var id: Self { self }

    fileprivate func title(copy: SubscriptionCopy) -> String {
        switch self {
        case .free: copy.freePlan
        case .plus: copy.plusPlan
        case .pro: copy.proTierPlan
        case .lifetime: copy.lifetimePlan
        }
    }

    fileprivate func subtitle(copy: SubscriptionCopy) -> String {
        switch self {
        case .free: copy.freeSubtitle
        case .plus: copy.plusSubtitle
        case .pro: copy.proSubtitle
        case .lifetime: copy.lifetimeSubtitle
        }
    }

    fileprivate func features(copy: SubscriptionCopy, period: SubscriptionBillingPeriod) -> [String] {
        switch self {
        case .free: copy.freeFeatures
        case .plus: copy.plusFeatures(period: period)
        case .pro: copy.proFeatures
        case .lifetime: copy.lifetimeFeatures
        }
    }

    fileprivate func unavailableMessage(period: SubscriptionBillingPeriod, copy: SubscriptionCopy) -> String {
        let periodName = period.title(copy: copy)
        switch self {
        case .free:
            return copy.freeUnavailable
        case .plus:
            return copy.isEnglish ? "Plus \(periodName) is unavailable right now." : "\(periodName)のPlusプランを読み込めませんでした。"
        case .pro:
            return copy.isEnglish ? "Pro \(periodName) is unavailable right now." : "\(periodName)のProプランを読み込めませんでした。"
        case .lifetime:
            return copy.isEnglish ? "Lifetime plan is unavailable right now." : "買い切りプランを読み込めませんでした。"
        }
    }
}

private struct SubscriptionCopy {
    let language: AppLanguage

    fileprivate var isEnglish: Bool { language == .english }

    var navigationTitle: String { isEnglish ? "Subscription" : "サブスクリプション" }
    var proPlan: String { isEnglish ? "StackCast Pro" : "StackCast Pro" }
    var proDescription: String { isEnglish ? "Your Pro features are ready to use." : "Proのすべての機能を利用できます。" }
    var choosePlan: String { isEnglish ? "Choose your plan" : "プランを選ぶ" }
    var upgradeTitle: String { isEnglish ? "Upgrade" : "アップグレード" }
    var upgradeMessage: String {
        isEnglish
            ? "Choose a plan that fits you."
            : "あなたに合ったプランを選択してください。"
    }
    var monthlyPlan: String { isEnglish ? "Monthly" : "月額" }
    var yearlyPlan: String { isEnglish ? "Yearly" : "年間" }
    var lifetimePlan: String { isEnglish ? "One-time" : "買い切り" }
    var month: String { isEnglish ? "month" : "月" }
    var year: String { isEnglish ? "year" : "年" }
    var currentPlan: String { isEnglish ? "Current" : "現在のプラン" }
    var planChangedTitle: String { isEnglish ? "Plan changed" : "プランが変更されました" }
    var planChangeDismiss: String { isEnglish ? "Done" : "確認" }
    func planChangedMessage(planName: String) -> String {
        isEnglish ? "Your plan is now \(planName)." : "現在のプランは\(planName)です。"
    }
    var freePlan: String { isEnglish ? "Free" : "Free" }
    var freePrice: String { isEnglish ? "$0.00" : "無料" }
    var freeSubtitle: String { isEnglish ? "A simple way to get started" : "まずは基本機能から" }
    var freeFeatures: [String] {
        isEnglish
            ? ["URL stock: up to 10 (5 days)", "Cast: 10 minutes only", "Cast creation: 3 per month"]
            : ["URLストック：10件まで（保存期間5日）", "Cast：10分のみ", "Cast作成：月3本まで"]
    }
    var freeUnavailable: String { isEnglish ? "Free plan is already active." : "Freeプランは現在のプランです。" }
    var plusPlan: String { "Plus" }
    var proTierPlan: String { "Pro" }
    var lifetimeSubtitle: String { isEnglish ? "Pay once, use it forever" : "一度の購入でずっと利用" }
    var plusSubtitle: String { isEnglish ? "More control for your listening" : "Castをもっと自由に楽しみたい方に" }
    var proSubtitle: String { isEnglish ? "For unlimited listening and saving" : "保存も再生も、もっと自由に" }
    func plusFeatures(period: SubscriptionBillingPeriod) -> [String] {
        if isEnglish {
            let castLimit = period == .monthly ? "Cast creation: up to 200/month" : "Cast creation: up to 2,400/year"
            let stockLimit = period == .monthly ? "URL stock: up to 70/month" : "URL stock: up to 700/year"
            return [
                "Cast duration: 5 to 20 minutes",
                castLimit,
                stockLimit,
                "Offline playback",
                "URL retention: 15 days"
            ]
        }

        let castLimit = period == .monthly ? "Cast作成：月200本まで" : "Cast作成：年2,400本まで"
        let stockLimit = period == .monthly ? "URLストック：月70件まで" : "URLストック：年700件まで"
        return [
            "Cast時間：5〜20分から設定",
            castLimit,
            stockLimit,
            "オフライン再生",
            "URL保存期間：15日"
        ]
    }
    var proFeatures: [String] {
        isEnglish ? ["Save even more articles", "All Cast durations", "Background playback"] : ["保存できる記事数がさらに増える", "すべてのCast時間", "バックグラウンド再生"]
    }
    var lifetimeFeatures: [String] {
        isEnglish ? ["All Pro features included", "No recurring charges"] : ["Proのすべての機能を利用", "追加の継続課金なし"]
    }
    var unavailable: String { isEnglish ? "Currently unavailable" : "現在利用できません" }
    var plan: String { isEnglish ? "Plan" : "プラン" }
    var renewalDate: String { isEnglish ? "Renews" : "次回更新日" }
    var endsOn: String { isEnglish ? "Ends" : "利用終了日" }
    var billingIssue: String { isEnglish ? "There is a billing issue. Please update your payment method." : "お支払いに問題があります。お支払い方法を更新してください。" }
    var benefitsTitle: String { isEnglish ? "With Pro" : "Proでできること" }
    var storageBenefit: String { isEnglish ? "More article storage" : "より多くの記事を保存" }
    var storageBenefitDetail: String { isEnglish ? "Keep more of what matters to you" : "あとで読みたい記事を、もっと残せます" }
    var digestBenefit: String { isEnglish ? "Every Cast duration" : "すべてのCast時間" }
    var digestBenefitDetail: String { isEnglish ? "Choose the listening length that fits your day" : "その日の予定に合った長さを選べます" }
    var playbackBenefit: String { isEnglish ? "Background playback" : "バックグラウンド再生" }
    var playbackBenefitDetail: String { isEnglish ? "Keep listening while you use other apps" : "ほかのアプリを使いながら聴けます" }
    var manageSubscription: String { isEnglish ? "Manage subscription" : "サブスクリプションを管理" }
    var restorePurchases: String { isEnglish ? "Restore purchases" : "購入を復元" }
    var moreActions: String { isEnglish ? "More actions" : "その他の操作" }
    var loadingPlans: String { isEnglish ? "Loading plans…" : "プランを読み込み中…" }
    var purchaseFootnote: String { isEnglish ? "Cancel anytime in your App Store account settings." : "いつでもApp Storeのアカウント設定からキャンセルできます。" }
    var autoRenewalTitle: String { isEnglish ? "About auto-renewal" : "自動更新について" }
    var autoRenewalNotice: String {
        isEnglish
            ? "Subscription automatically renews unless canceled at least 24 hours before the end of the current period."
            : "サブスクリプションは自動更新されます。現在の期間終了の24時間以上前までに解約してください。"
    }
    var lifetimePurchaseNotice: String { isEnglish ? "One-time purchase. No recurring charges." : "買い切り購入です。継続課金はありません。" }
    var termsOfUse: String { isEnglish ? "Terms of Use" : "利用規約" }
    var privacyPolicy: String { isEnglish ? "Privacy Policy" : "プライバシーポリシー" }
    var billingDisclosureTitle: String { isEnglish ? "Billing details" : "課金について" }
    var billingDisclosure: String {
        isEnglish
            ? "The displayed price is charged through your Apple ID. Monthly and yearly plans renew automatically unless canceled at least 24 hours before the current period ends. You can cancel or manage your subscription in Apple ID Settings."
            : "表示価格はApple IDを通じて請求されます。月額・年額プランは、現在の期間終了の24時間以上前までに解約しない限り自動更新されます。解約・管理はApple IDのサブスクリプション設定から行えます。"
    }

    func startPro(tier: SubscriptionTier, period: SubscriptionBillingPeriod, price: String) -> String {
        let tierName = tier.title(copy: self)
        switch period {
        case .monthly:
            return isEnglish ? "Start \(tierName) · \(price)/month" : "\(tierName)をはじめる · \(price)/月"
        case .yearly:
            return isEnglish ? "Start \(tierName) · \(price)/year" : "\(tierName)をはじめる · \(price)/年"
        case .lifetime:
            return isEnglish ? "Buy \(tierName) · \(price)" : "\(tierName)を買い切りで購入 · \(price)"
        }
    }
}

private struct SubscriptionMenuGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(.white).interactive(), in: .circle)
        } else {
            content
                .background(.white.opacity(0.9), in: Circle())
                .overlay(Circle().strokeBorder(.quaternary, lineWidth: 0.5))
        }
    }
}

private struct CloseButtonGlassBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.tint(.white).interactive(), in: .circle)
        } else {
            content
                .background(.white.opacity(0.9), in: Circle())
        }
    }
}

#Preview("Free plan") {
    NavigationStack {
        SubscriptionManagementView(
            subscriptionStore: SubscriptionStore(),
            language: .japanese,
            loadsSubscriptionData: false
        )
    }
}

#Preview("Free plan · English") {
    NavigationStack {
        SubscriptionManagementView(
            subscriptionStore: SubscriptionStore(),
            language: .english,
            loadsSubscriptionData: false
        )
    }
}
