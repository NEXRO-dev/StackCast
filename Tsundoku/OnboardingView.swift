//
//  OnboardingView.swift
//  Tsundoku
//

import SwiftUI

struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var selectedPage = 0

    private let pages = OnboardingPage.all

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [pages[selectedPage].color.opacity(0.10), Color(.systemBackground), Color(.systemBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("スキップ", action: onFinish)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .opacity(isLastPage ? 0 : 1)
                        .disabled(isLastPage)
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)

                TabView(selection: $selectedPage) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        OnboardingPageView(page: page)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                VStack(spacing: 14) {
                    HStack(spacing: 6) {
                        ForEach(pages.indices, id: \.self) { index in
                            Capsule()
                                .fill(index == selectedPage ? pages[selectedPage].color : Color.secondary.opacity(0.20))
                                .frame(width: index == selectedPage ? 24 : 7, height: 7)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("全\(pages.count)ページ中、\(selectedPage + 1)ページ目")

                    Button(action: advance) {
                        HStack(spacing: 8) {
                            Text(isLastPage ? "アカウントを作成" : "次へ")
                            Image(systemName: isLastPage ? "arrow.right" : "chevron.right")
                                .font(.subheadline.weight(.bold))
                        }
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(pages[selectedPage].color)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .animation(.easeInOut(duration: 0.2), value: selectedPage)
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 20)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: selectedPage)
    }

    private var isLastPage: Bool {
        selectedPage == pages.count - 1
    }

    private func advance() {
        if isLastPage {
            onFinish()
        } else {
            withAnimation(.snappy) {
                selectedPage += 1
            }
        }
    }
}

private struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 12)

            OnboardingIllustration(systemImage: page.systemImage, color: page.color)
            .accessibilityHidden(true)

            VStack(spacing: 14) {
                Text(page.title)
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
                Text(page.message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 28)

            Spacer(minLength: 12)
        }
        .padding(.vertical, 12)
    }
}

struct OnboardingIllustration: View {
    let systemImage: String
    let color: Color

    var body: some View {
        Image(assetName)
            .resizable()
            .scaledToFit()
            .frame(width: 304, height: 304)
        .shadow(color: color.opacity(0.16), radius: 22, y: 12)
    }

    private var assetName: String {
        switch systemImage {
        case "discover.news": return "OnboardingDiscover"
        case "save.articles": return "OnboardingSave"
        case "reading.pace": return "OnboardingReading"
        case "cast.audio": return "OnboardingCast"
        case "listen": return "OnboardingListen"
        default: return "OnboardingDiscover"
        }
    }
}

private struct OnboardingPage {
    let systemImage: String
    let title: String
    let message: String
    let color: Color

    static let all = [
        OnboardingPage(
            systemImage: "discover.news",
            title: "気になるニュースに、\n出会える",
            message: "見逃していた話題も、\nあなたの興味から見つけます。",
            color: .indigo
        ),
        OnboardingPage(
            systemImage: "save.articles",
            title: "あなた向けの\nニュース",
            message: "興味のあるジャンルから、\n毎日のニュースをお届けします。",
            color: .indigo
        ),
        OnboardingPage(
            systemImage: "reading.pace",
            title: "気になったら、\nあとで読む",
            message: "保存した記事は、\nあなたのペースで楽しめます。",
            color: .orange
        ),
        OnboardingPage(
            systemImage: "cast.audio",
            title: "ニュースをCastにして\n聴く",
            message: "あなた向けのニュースを、\nわかりやすい音声に変えます。",
            color: .pink
        ),
        OnboardingPage(
            systemImage: "listen",
            title: "見ていない時間も、\n知識に変わる",
            message: "移動中や家事の時間も、\n耳でニュースを楽しめます。",
            color: .teal
        )
    ]
}

#Preview {
    OnboardingView {}
}
