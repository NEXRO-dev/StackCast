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
                    Button("Skip", action: onFinish)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
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

                VStack(spacing: 14) {
                    HStack(spacing: 6) {
                        ForEach(pages.indices, id: \.self) { index in
                            Capsule()
                                .fill(index == selectedPage ? pages[selectedPage].color : Color.secondary.opacity(0.20))
                                .frame(width: index == selectedPage ? 24 : 7, height: 7)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Page \(selectedPage + 1) of \(pages.count)")

                    Button(action: advance) {
                        HStack(spacing: 8) {
                            Text(isLastPage ? "Create an Account" : "Next")
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

private struct OnboardingPageViewEN: View {
    let page: OnboardingPageEN

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

private struct OnboardingPageEN {
    let systemImage: String
    let title: String
    let message: String
    let color: Color

    static let all = [
        OnboardingPageEN(
            systemImage: "discover.news",
            title: "Discover News\nThat Matters to You",
            message: "Find stories you might have missed,\nshaped by your interests.",
            color: .indigo
        ),
        OnboardingPageEN(
            systemImage: "save.articles",
            title: "News\nJust for You",
            message: "Get a daily selection built\nfrom the topics you care about.",
            color: .indigo
        ),
        OnboardingPageEN(
            systemImage: "reading.pace",
            title: "Save It and\nRead at Your Pace",
            message: "Keep articles for later\nand come back whenever you like.",
            color: .orange
        ),
        OnboardingPageEN(
            systemImage: "cast.audio",
            title: "Turn News\ninto a Cast",
            message: "Transform your personalized news\ninto clear, easy-to-listen audio.",
            color: .pink
        ),
        OnboardingPageEN(
            systemImage: "listen",
            title: "Learn Without\nLooking at a Screen",
            message: "Enjoy your news while commuting,\nworking out, or doing chores.",
            color: .teal
        )
    ]
}

#Preview {
    OnboardingViewEN {}
}
