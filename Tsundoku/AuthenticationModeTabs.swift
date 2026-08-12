//
//  AuthenticationModeTabs.swift
//  Tsundoku
//

import SwiftUI

struct AuthenticationModeTabs: View {
    let language: AppLanguage
    let isLoginSelected: Bool
    let onSelectSignup: () -> Void
    let onSelectLogin: () -> Void

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
                .frame(width: 112, height: 34)
                .offset(x: isLoginSelected ? 114 : 0)

            HStack(spacing: 2) {
                tabButton(
                    title: language == .english ? "Sign up" : "サインアップ",
                    isSelected: !isLoginSelected,
                    action: onSelectSignup
                )
                tabButton(
                    title: language == .english ? "Log in" : "ログイン",
                    isSelected: isLoginSelected,
                    action: onSelectLogin
                )
            }
        }
        .padding(3)
        .background(.thinMaterial, in: Capsule())
        .overlay { Capsule().stroke(.primary.opacity(0.08), lineWidth: 1) }
        .animation(.snappy(duration: 0.28), value: isLoginSelected)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(language == .english ? "Authentication mode" : "認証モード")
    }

    private func tabButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .frame(width: 112, height: 34)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    VStack(spacing: 24) {
        AuthenticationModeTabs(language: .japanese, isLoginSelected: false, onSelectSignup: {}, onSelectLogin: {})
        AuthenticationModeTabs(language: .english, isLoginSelected: true, onSelectSignup: {}, onSelectLogin: {})
    }
    .padding()
}
