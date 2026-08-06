//
//  SettingsViewEN.swift
//  Tsundoku
//

import SwiftUI

struct SettingsViewEN: View {
    let authStore: AuthStore

    @AppStorage(AppLanguage.storageKey) private var appLanguage = AppLanguage.english.rawValue
    @State private var notificationsEnabled = true
    @State private var defaultDuration = 10
    @State private var defaultSpeed = 1.0
    @State private var isShowingPro = false

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                languageSection
                planSection
                playbackSection
                notificationSection
                supportSection
                appSection
            }
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .sheet(isPresented: $isShowingPro) {
                ProPlanSheetEN()
            }
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

    private var planSection: some View {
        Section {
            Button {
                isShowingPro = true
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                        Image(systemName: "sparkles")
                            .foregroundStyle(.white)
                    }
                    .frame(width: 52, height: 52)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Free Plan")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("Get more freedom with Pro")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            Button("Restore Purchases", systemImage: "arrow.clockwise") {}
        } header: {
            Text("Plan")
        }
    }

    private var playbackSection: some View {
        Section("Digest") {
            Picker("Default Duration", selection: $defaultDuration) {
                ForEach([5, 10, 15, 30], id: \.self) { duration in
                    Text("\(duration) min").tag(duration)
                }
            }

            Picker("Default Playback Speed", selection: $defaultSpeed) {
                ForEach([1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                    Text("\(speed.formatted())x").tag(speed)
                }
            }
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
                ContentUnavailableView("Coming Soon", systemImage: "hammer")
            } label: {
                Label("How to Use StashCast", systemImage: "questionmark.circle")
            }
            Link(destination: URL(string: "https://example.com/terms")!) {
                Label("Terms of Service", systemImage: "doc.text")
            }
            Link(destination: URL(string: "https://example.com/privacy")!) {
                Label("Privacy Policy", systemImage: "hand.raised")
            }
        }
    }

    private var appSection: some View {
        Section("App Information") {
            LabeledContent("Version", value: appVersion)
            LabeledContent("Article Expiration", value: "5 days")
        }
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

            if case .signedIn = authStore.status {
                Button("Log Out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    Task {
                        await authStore.logout()
                    }
                }
            }
        }
    }
}

private struct ProPlanSheetEN: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 54))
                        .foregroundStyle(.indigo)
                        .padding(24)
                        .background(.indigo.opacity(0.12), in: Circle())

                    VStack(spacing: 8) {
                        Text("StashCast Pro")
                            .font(.largeTitle.bold())
                        Text("Save and listen without\nworrying about limits.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        proFeature("Higher article storage limits", symbol: "tray.full")
                        proFeature("Every digest duration", symbol: "clock")
                        proFeature("Background playback", symbol: "headphones")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .tsundokuCard()

                    Button("View Plans") {}
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                }
                .padding(24)
            }
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func proFeature(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.headline)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.indigo)
    }
}

#Preview {
    SettingsViewEN(authStore: AuthStore())
}
