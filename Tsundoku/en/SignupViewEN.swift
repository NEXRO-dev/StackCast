//
//  SignupViewEN.swift
//  Tsundoku
//

import SwiftUI

struct SignupViewEN: View {
    let authStore: AuthStore
    let onBack: () -> Void
    let onComplete: () -> Void
    let onShowLogin: () -> Void

    var body: some View {
        SignupCardView(
            authStore: authStore,
            copy: .english,
            onBack: onBack,
            onComplete: onComplete,
            onShowLogin: onShowLogin
        )
    }
}

#Preview {
    SignupViewEN(authStore: AuthStore(), onBack: {}, onComplete: {}, onShowLogin: {})
}
