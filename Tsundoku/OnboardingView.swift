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
        VStack(spacing: 0) {
            HStack {
                Spacer()

                Button("スキップ", action: onFinish)
                    .font(.subheadline.weight(.semibold))
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

            VStack(spacing: 24) {
                HStack(spacing: 8) {
                    ForEach(pages.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == selectedPage ? Color.accentColor : Color.secondary.opacity(0.25))
                            .frame(width: index == selectedPage ? 24 : 8, height: 8)
                    }
                }
                .animation(.snappy, value: selectedPage)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("全4ページ中、\(selectedPage + 1)ページ目")

                Button(action: advance) {
                    HStack {
                        Text(isLastPage ? "アカウントを作成" : "次へ")

                        if !isLastPage {
                            Image(systemName: "arrow.right")
                        }
                    }
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(Color(.systemBackground))
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
        VStack(spacing: 36) {
            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 48, style: .continuous)
                    .fill(page.color.opacity(0.12))
                    .frame(width: 240, height: 240)

                Image(systemName: page.systemImage)
                    .font(.system(size: 92, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(page.color)
            }
            .accessibilityHidden(true)

            VStack(spacing: 14) {
                Text(page.title)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)

                Text(page.message)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
            }
            .padding(.horizontal, 28)

            Spacer()
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
            systemImage: "link.circle.fill",
            title: "あとで読むを、\nひとつの場所に",
            message: "気になったWeb記事を共有するだけ。\n読みたい情報をすっきり保存できます。",
            color: .indigo
        ),
        OnboardingPage(
            systemImage: "hourglass.circle.fill",
            title: "5日間で、\n気持ちよく手放す",
            message: "期限が近い記事から優先して整理。\n未読が増え続ける負担を減らします。",
            color: .orange
        ),
        OnboardingPage(
            systemImage: "timer.circle.fill",
            title: "空き時間に\nぴったり収まる",
            message: "5分、10分、15分、20分から選ぶと、\n記事をCastにまとめます。",
            color: .pink
        ),
        OnboardingPage(
            systemImage: "headphones.circle.fill",
            title: "画面を見ずに、\n記事を消化",
            message: "要約を音声で連続再生。\n移動や家事の時間をニュース時間に変えます。",
            color: .teal
        )
    ]
}

#Preview {
    OnboardingView {}
}
