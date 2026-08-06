//
//  OnboardingViewEN.swift
//  Tsundoku
//

import SwiftUI

struct OnboardingViewEN: View {
    let onFinish: () -> Void

    @State private var selectedPage = 0

    private let pages = OnboardingPageEN.all

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()

                Button("Skip", action: onFinish)
                    .font(.subheadline.weight(.semibold))
                    .opacity(isLastPage ? 0 : 1)
                    .disabled(isLastPage)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            TabView(selection: $selectedPage) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    OnboardingPageViewEN(page: page)
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
                .accessibilityLabel("Page \(selectedPage + 1) of 4")

                Button(action: advance) {
                    HStack {
                        Text(isLastPage ? "Create an Account" : "Next")

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

private struct OnboardingPageViewEN: View {
    let page: OnboardingPageEN

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

private struct OnboardingPageEN {
    let systemImage: String
    let title: String
    let message: String
    let color: Color

    static let all = [
        OnboardingPageEN(
            systemImage: "link.circle.fill",
            title: "Save It for Later,\nAll in One Place",
            message: "Share any article that catches your eye.\nKeep everything you want to read organized.",
            color: .indigo
        ),
        OnboardingPageEN(
            systemImage: "hourglass.circle.fill",
            title: "Let It Go\nWithin Five Days",
            message: "We prioritize articles nearing expiration,\nso your unread list never feels overwhelming.",
            color: .orange
        ),
        OnboardingPageEN(
            systemImage: "timer.circle.fill",
            title: "A Digest That Fits\nYour Free Time",
            message: "Choose 5, 10, 15, or 30 minutes.\nWe'll build a digest that fits.",
            color: .pink
        ),
        OnboardingPageEN(
            systemImage: "headphones.circle.fill",
            title: "Catch Up Without\nLooking at a Screen",
            message: "Listen to article summaries back to back.\nTurn commutes and chores into news time.",
            color: .teal
        )
    ]
}

#Preview {
    OnboardingViewEN {}
}
