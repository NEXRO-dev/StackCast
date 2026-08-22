//
//  SettingsView.swift
//  Tsundoku
//

import SwiftUI
import Observation
import RevenueCat

@MainActor
@Observable
final class SubscriptionStore {
    private(set) var offering: Offering?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var managementURL: URL?
    private(set) var activeProductIdentifier: String?
    private(set) var expirationDate: Date?
    private(set) var willRenew = false
    private(set) var hasBillingIssue = false
    private(set) var serverSubscription: BillingSubscriptionSnapshot?
    private(set) var effectivePlanTier: SubscriptionPlanTier
    private(set) var revenueCatPlanTier: SubscriptionPlanTier = .free
    private var sessionToken: String?
    private var revenueCatUserID: String?

    init() {
        switch SharedArticleRepository.subscriptionTier {
        case .free: effectivePlanTier = .free
        case .plus: effectivePlanTier = .plus
        case .pro: effectivePlanTier = .pro
        case .lifetime: effectivePlanTier = .lifetime
        }
    }

    func clearError() {
        errorMessage = nil
    }

    var subscriptionManagementURL: URL? {
        managementURL ?? URL(string: "https://apps.apple.com/account/subscriptions")
    }

    var monthlyPackage: Package? {
        offering?.monthly ?? offering?.availablePackages.first
    }

    var yearlyPackage: Package? {
        offering?.annual
    }

    var lifetimePackage: Package? {
        offering?.lifetime
    }

    var planTier: SubscriptionPlanTier {
        effectivePlanTier
    }

    var isPro: Bool {
        effectivePlanTier != .free
    }

    var activeBillingPlanTier: SubscriptionPlanTier {
        if let billingIsActive = serverSubscription?.billingIsActive {
            guard billingIsActive,
                  let rawTier = serverSubscription?.billingPlanTier else { return .free }
            return subscriptionPlanTier(rawTier)
        }
        return revenueCatPlanTier
    }

    var hasActiveStoreSubscription: Bool {
        activeBillingPlanTier != .free && activeBillingPlanTier != .lifetime
    }

    func planTitle(language: AppLanguage) -> String {
        let title = planTier.title(language: language)
        guard planTier == .plus || planTier == .pro else { return title }

        let identifier = activeProductIdentifier?.lowercased() ?? ""
        if identifier.contains("annual") || identifier.contains("yearly") || identifier.contains("year") {
            return language == .english ? "\(title) / Yearly" : "\(title) / 年額"
        }

        return language == .english ? "\(title) / Monthly" : "\(title) / 月額"
    }

    func identify(userID: String, sessionToken: String?) async {
        isLoading = true
        errorMessage = nil
        self.sessionToken = sessionToken
        revenueCatUserID = userID

        do {
            _ = try await Purchases.shared.logIn(userID)
            await refresh()
        } catch {
            isLoading = false
            errorMessage = "SUBSCRIPTION_ERROR"
        }
    }

    func signOut() async {
        do {
            _ = try await Purchases.shared.logOut()
        } catch {
            // RevenueCatが匿名ユーザーへ戻れない場合でも、アプリのログアウトは継続します。
        }

        offering = nil
        effectivePlanTier = .free
        revenueCatPlanTier = .free
        errorMessage = nil
        managementURL = nil
        activeProductIdentifier = nil
        expirationDate = nil
        willRenew = false
        hasBillingIssue = false
        serverSubscription = nil
        sessionToken = nil
        revenueCatUserID = nil
        SharedArticleRepository.setSubscriptionTier(.free)
    }

    func refresh() async {
        do {
            let offerings = try await Purchases.shared.offerings()
            offering = offerings.current

            let customerInfo = try await Purchases.shared.customerInfo()
            updateRevenueCatMetadata(from: customerInfo)
        } catch {
            errorMessage = "SUBSCRIPTION_ERROR"
        }

        // Access control is sourced from the backend DB even when RevenueCat
        // metadata or offerings are temporarily unavailable on this device.
        await refreshServerSubscription()

        isLoading = false
    }

    func purchaseMonthly() async {
        guard let package = monthlyPackage else {
            errorMessage = "購入できる月額プランを取得できませんでした。"
            return
        }

        await purchase(package: package)
    }

    func purchase(package: Package) async {

        isLoading = true
        errorMessage = nil

        do {
            // The app can be relaunched with RevenueCat anonymous even when
            // the backend session is already restored. Re-identify immediately
            // before purchasing so the receipt belongs to the signed-in user.
            if let revenueCatUserID {
                _ = try await Purchases.shared.logIn(revenueCatUserID)
            }
            let result = try await Purchases.shared.purchase(package: package)
            updateRevenueCatMetadata(from: result.customerInfo)
            await refreshServerSubscription(waitingForProduct: package.storeProduct.productIdentifier)
        } catch {
            errorMessage = "SUBSCRIPTION_ERROR"
        }

        isLoading = false
    }

    func restorePurchases() async {
        isLoading = true
        errorMessage = nil

        do {
            let customerInfo = try await Purchases.shared.restorePurchases()
            updateRevenueCatMetadata(from: customerInfo)
            await refreshServerSubscription(waitingForActivePlan: true)
        } catch {
            errorMessage = "SUBSCRIPTION_ERROR"
        }

        isLoading = false
    }

    private func updateRevenueCatMetadata(from customerInfo: CustomerInfo) {
        let entitlement = customerInfo.entitlements[Config.revenueCatEntitlementID]
        revenueCatPlanTier = entitlement?.isActive == true
            ? subscriptionPlanTier(entitlement?.productIdentifier ?? "free")
            : .free
        managementURL = customerInfo.managementURL
        activeProductIdentifier = entitlement?.productIdentifier
        expirationDate = entitlement?.expirationDate
        willRenew = entitlement?.willRenew == true
        hasBillingIssue = entitlement?.billingIssueDetectedAt != nil
    }

    private func refreshServerSubscription(
        waitingForProduct expectedProduct: String? = nil,
        waitingForActivePlan: Bool = false
    ) async {
        guard let sessionToken else { return }
        let attempts = expectedProduct == nil && !waitingForActivePlan ? 1 : 8

        for attempt in 0..<attempts {
            do {
                let subscription = try await AuthClient().billingSubscription(token: sessionToken)
                serverSubscription = subscription
                applyServerSubscription(subscription)

                let productMatches = expectedProduct == nil
                    || subscription?.productId == expectedProduct
                let activeMatches = !waitingForActivePlan
                    || subscription?.effectiveIsActive == true
                    || subscription?.isActive == true
                if productMatches && activeMatches { return }
            } catch {
                if attempt == attempts - 1 {
                    errorMessage = "SUBSCRIPTION_ERROR"
                    return
                }
            }

            if attempt < attempts - 1 {
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func applyServerSubscription(_ subscription: BillingSubscriptionSnapshot?) {
        guard let subscription else {
            applyEffectivePlan(.free)
            return
        }

        let isActive = subscription.effectiveIsActive ?? subscription.isActive
        let rawTier = subscription.effectivePlanTier
            ?? subscription.planTier
            ?? "free"
        let tier = isActive ? subscriptionPlanTier(rawTier) : .free
        applyEffectivePlan(tier)

        activeProductIdentifier = subscription.source == "admin_override"
            ? (tier == .free ? nil : "\(rawTier.lowercased())_admin_override")
            : subscription.productId
        expirationDate = parseServerDate(subscription.overrideExpiresAt ?? subscription.expiresAt)
        if subscription.source == "admin_override" {
            willRenew = false
            hasBillingIssue = false
        }
    }

    private func applyEffectivePlan(_ tier: SubscriptionPlanTier) {
        effectivePlanTier = tier
        SharedArticleRepository.setSubscriptionTier(sharedSubscriptionTier)
    }

    private func subscriptionPlanTier(_ value: String) -> SubscriptionPlanTier {
        let normalized = value.lowercased()
        if normalized.contains("lifetime") || normalized.contains("one-time") || normalized.contains("onetime") {
            return .lifetime
        }
        if normalized.contains("plus") { return .plus }
        if normalized.contains("pro") { return .pro }
        return .free
    }

    private func parseServerDate(_ value: String?) -> Date? {
        guard let value else { return nil }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }

        return ISO8601DateFormatter().date(from: value)
    }

    private var sharedSubscriptionTier: SharedSubscriptionTier {
        switch planTier {
        case .free: .free
        case .plus: .plus
        case .pro: .pro
        case .lifetime: .lifetime
        }
    }
}

enum SubscriptionPlanTier: Equatable {
    case free
    case plus
    case pro
    case lifetime

    func title(language: AppLanguage) -> String {
        switch self {
        case .free:
            language == .english ? "Free Plan" : "Freeプラン"
        case .plus:
            language == .english ? "Plus Plan" : "Plusプラン"
        case .pro:
            language == .english ? "Pro Plan" : "Proプラン"
        case .lifetime:
            language == .english ? "Lifetime Plan" : "Lifetimeプラン"
        }
    }
}

enum SettingsDestructiveAction: Identifiable {
    case logout
    case deleteAccount
    case error(String)

    var id: String {
        switch self {
        case .logout: "logout"
        case .deleteAccount: "deleteAccount"
        case .error(let message): "error:\(message)"
        }
    }
}

struct SettingsView: View {
    let authStore: AuthStore
    let playbackStore: CastPlaybackStore

    @AppStorage(AppLanguage.storageKey) private var appLanguage = AppLanguage.japanese.rawValue
    @AppStorage(AppAppearance.storageKey) private var appAppearance = AppAppearance.system.rawValue
    @State private var notificationsEnabled = true
    @AppStorage(castDefaultDurationKey) private var defaultDuration = 10
    @AppStorage(castPlaybackRateKey) private var defaultSpeed = 1.0
    @State private var isShowingSubscription = false
    @State private var isShowingAIDataUse = false
    @State private var browserDestination: InAppBrowserDestination?
    @State private var destructiveAction: SettingsDestructiveAction?
    let subscriptionStore: SubscriptionStore

    var body: some View {
        NavigationStack {
            Form {
                languageSection
                appearanceSection
                playbackSection
                notificationSection
                dataUseSection
                supportSection
                appSection
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable {
                await subscriptionStore.refresh()
            }
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .listSectionSpacing(.custom(4))
            .sheet(isPresented: $isShowingSubscription) {
                SubscriptionManagementView(subscriptionStore: subscriptionStore, language: .japanese)
            }
            .sheet(isPresented: $isShowingAIDataUse) {
                AIDataConsentSheet(language: .japanese)
            }
            .sheet(item: $browserDestination) { destination in
                InAppBrowserView(url: destination.url)
            }
            .alert(item: $destructiveAction) { action in
                destructiveAlert(for: action)
            }
        }
    }

    private func destructiveAlert(for action: SettingsDestructiveAction) -> Alert {
        switch action {
        case .logout:
            Alert(
                title: Text("ログアウトしますか？"),
                message: Text("現在のアカウントからログアウトします。"),
                primaryButton: .destructive(Text("ログアウト")) {
                    Task { await authStore.logout() }
                },
                secondaryButton: .cancel(Text("キャンセル"))
            )
        case .deleteAccount:
            Alert(
                title: Text("アカウントを削除しますか？"),
                message: Text("アカウントと関連するデータは完全に削除され、元に戻せません。"),
                primaryButton: .destructive(Text("削除する")) {
                    Task { await deleteAccount() }
                },
                secondaryButton: .cancel(Text("キャンセル"))
            )
        case .error(let message):
            Alert(
                title: Text("エラー"),
                message: Text(message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func deleteAccount() async {
        do {
            try await authStore.deleteAccount()
        } catch {
            destructiveAction = .error("アカウントを削除できませんでした。もう一度お試しください。")
        }
    }

    private var languageSection: some View {
        Section("言語") {
            Picker("表示言語", selection: $appLanguage) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.displayName).tag(language.rawValue)
                }
            }
        }
    }

    private var appearanceSection: some View {
        Section("外観") {
            Picker("表示モード", selection: $appAppearance) {
                ForEach(AppAppearance.allCases) { appearance in
                    Text(appearance.displayName(isEnglish: false)).tag(appearance.rawValue)
                }
            }
        }
    }

    private var planSection: some View {
        Section {
            NavigationLink {
                SubscriptionManagementView(
                    subscriptionStore: subscriptionStore,
                    language: AppLanguage(rawValue: appLanguage) ?? .japanese,
                    showsUpgradeHeader: false
                )
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(subscriptionStore.planTitle(language: .japanese))
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("プランを確認・変更")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } header: {
            Text("プラン")
        }
    }

    private var playbackSection: some View {
        Section("Cast") {
            Picker("既定の時間", selection: $defaultDuration) {
                ForEach(Array(5...20), id: \.self) { duration in
                    Text("\(duration)分").tag(duration)
                }
            }
            .onChange(of: defaultDuration) { _, duration in
                guard subscriptionStore.isPro || duration == 10 else {
                    defaultDuration = 10
                    isShowingSubscription = true
                    return
                }
            }

            Picker("既定の再生速度", selection: $defaultSpeed) {
                ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                    Text("\(speed.formatted())x").tag(speed)
                }
            }
            .onChange(of: defaultSpeed) { _, speed in
                playbackStore.setPlaybackRate(speed)
            }

            LabeledContent("URLコンテンツの保存期間", value: "5日間")
        }
    }

    private var notificationSection: some View {
        Section {
            Toggle("期限が近い記事を通知", isOn: $notificationsEnabled)
        } header: {
            Text("通知")
        } footer: {
            Text("期限まで24時間以内の記事があるときにお知らせします。")
        }
    }

    private var supportSection: some View {
        Section("サポート") {
            NavigationLink {
                SupportView(language: .japanese)
            } label: {
                Label("サポートに問い合わせ", systemImage: "envelope")
            }
            Button {} label: {
                Label("使い方", systemImage: "questionmark.circle")
            }
            .disabled(true)
            Button {
                browserDestination = InAppBrowserDestination(url: URL(string: "https://stackcast.app/terms")!)
            } label: {
                Label("利用規約", systemImage: "doc.text")
            }
            Button {
                browserDestination = InAppBrowserDestination(url: URL(string: "https://stackcast.app/privacy")!)
            } label: {
                Label("プライバシーポリシー", systemImage: "hand.raised")
            }
        }
    }

    private var dataUseSection: some View {
        Section {
            Button {
                isShowingAIDataUse = true
            } label: {
                Label("記事とAI処理について", systemImage: "doc.text")
                    .foregroundStyle(Color.black)
            }
        } header: {
            Text("データ利用")
        }
    }

    private var appSection: some View {
        Section("アプリ情報") {
            LabeledContent("バージョン", value: appVersion)
        }
    }

    private var logoutSection: some View {
        Section("危険な操作") {
            Button {
                destructiveAction = .logout
            } label: {
                Label("ログアウト", systemImage: "rectangle.portrait.and.arrow.right")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.red, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                destructiveAction = .deleteAccount
            } label: {
                Label("アカウントを削除", systemImage: "person.crop.circle.badge.minus")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 16, trailing: 20))
    }

    private var dangerSectionDivider: some View {
        Section {
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(maxWidth: .infinity)
                .frame(height: 1)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
        .listRowSeparator(.hidden)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "1.0.0"
    }

    private var accountSection: some View {
        Section("アカウント") {
            switch authStore.status {
            case .signedIn(let user):
                HStack(spacing: 14) {
                    AccountAvatarView(user: user)
                    .frame(width: 48, height: 48)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("ログイン中")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(user.name)
                            .font(.headline)
                        Text(user.email)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .textSelection(.enabled)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)

            case .checking:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("アカウントを確認中…")
                        .foregroundStyle(.secondary)
                }

            case .signedOut:
                Label("ログインしていません", systemImage: "person.crop.circle.badge.xmark")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    SettingsView(authStore: AuthStore(), playbackStore: CastPlaybackStore(), subscriptionStore: SubscriptionStore())
}
