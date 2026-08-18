//
//  SettingsViewEN.swift
//  Tsundoku
//

import SwiftUI

struct SettingsViewEN: View {
    let authStore: AuthStore
    let playbackStore: CastPlaybackStore

    @AppStorage(AppLanguage.storageKey) private var appLanguage = AppLanguage.english.rawValue
    @AppStorage(AppAppearance.storageKey) private var appAppearance = AppAppearance.system.rawValue
    @State private var notificationsEnabled = true
    @State private var defaultDuration = 10
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
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .listSectionSpacing(.custom(4))
            .sheet(isPresented: $isShowingSubscription) {
                SubscriptionManagementView(subscriptionStore: subscriptionStore, language: .english)
            }
            .sheet(isPresented: $isShowingAIDataUse) {
                AIDataConsentSheet(language: .english)
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
                title: Text("Log out?"),
                message: Text("You will be signed out of your current account."),
                primaryButton: .destructive(Text("Log Out")) {
                    Task { await authStore.logout() }
                },
                secondaryButton: .cancel(Text("Cancel"))
            )
        case .deleteAccount:
            Alert(
                title: Text("Delete account?"),
                message: Text("Your account and related data will be permanently deleted. This cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    Task { await deleteAccount() }
                },
                secondaryButton: .cancel(Text("Cancel"))
            )
        case .error(let message):
            Alert(
                title: Text("Error"),
                message: Text(message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func deleteAccount() async {
        do {
            try await authStore.deleteAccount()
        } catch {
            destructiveAction = .error("Could not delete your account. Please try again.")
        }
    }

    private var languageSection: some View {
        Section("Language") {
            Picker("Display Language", selection: $appLanguage) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.displayName).tag(language.rawValue)
                }
            }
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Display Mode", selection: $appAppearance) {
                ForEach(AppAppearance.allCases) { appearance in
                    Text(appearance.displayName(isEnglish: true)).tag(appearance.rawValue)
                }
            }
        }
    }

    private var planSection: some View {
        Section {
            NavigationLink {
                SubscriptionManagementView(
                    subscriptionStore: subscriptionStore,
                    language: .english,
                    showsUpgradeHeader: false
                )
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(subscriptionStore.planTitle(language: .english))
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("View or change plan")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } header: {
            Text("Plan")
        }
    }

    private var playbackSection: some View {
        Section("Cast") {
            Picker("Default Duration", selection: $defaultDuration) {
                ForEach([5, 10, 15, 20], id: \.self) { duration in
                    Text("\(duration) min").tag(duration)
                }
            }
            .onChange(of: defaultDuration) { _, duration in
                guard subscriptionStore.isPro || duration == 10 else {
                    defaultDuration = 10
                    isShowingSubscription = true
                    return
                }
            }

            Picker("Default Playback Speed", selection: $defaultSpeed) {
                ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                    Text("\(speed.formatted())x").tag(speed)
                }
            }
            .onChange(of: defaultSpeed) { _, speed in
                playbackStore.setPlaybackRate(speed)
            }

            LabeledContent("URL Content Retention", value: "5 days")
        }
    }

    private var notificationSection: some View {
        Section {
            Toggle("Notify Me Before Articles Expire", isOn: $notificationsEnabled)
        } header: {
            Text("Notifications")
        } footer: {
            Text("We'll notify you when an article has less than 24 hours left.")
        }
    }

    private var supportSection: some View {
        Section("Support") {
            NavigationLink {
                SupportView(language: .english)
            } label: {
                Label("Contact Support", systemImage: "envelope")
            }
            Button {} label: {
                Label("How to Use StackCast", systemImage: "questionmark.circle")
            }
            .disabled(true)
            Button {
                browserDestination = InAppBrowserDestination(url: URL(string: "https://stackcast.app/terms")!)
            } label: {
                Label("Terms of Service", systemImage: "doc.text")
            }
            Button {
                browserDestination = InAppBrowserDestination(url: URL(string: "https://stackcast.app/privacy")!)
            } label: {
                Label("Privacy Policy", systemImage: "hand.raised")
            }
        }
    }

    private var dataUseSection: some View {
        Section {
            Button {
                isShowingAIDataUse = true
            } label: {
                Label("Articles and AI processing", systemImage: "doc.text")
                    .foregroundStyle(Color.black)
            }
        } header: {
            Text("Data Use")
        }
    }

    private var appSection: some View {
        Section("App Information") {
            LabeledContent("Version", value: appVersion)
        }
    }

    private var logoutSection: some View {
        Section("Danger Zone") {
            Button {
                destructiveAction = .logout
            } label: {
                Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
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
                Label("Delete Account", systemImage: "person.crop.circle.badge.minus")
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
        Section("Account") {
            switch authStore.status {
            case .signedIn(let user):
                HStack(spacing: 14) {
                    AccountAvatarView(user: user)
                    .frame(width: 48, height: 48)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Signed in")
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
                    Text("Checking account…")
                        .foregroundStyle(.secondary)
                }

            case .signedOut:
                Label("Not signed in", systemImage: "person.crop.circle.badge.xmark")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    SettingsViewEN(authStore: AuthStore(), playbackStore: CastPlaybackStore(), subscriptionStore: SubscriptionStore())
}
