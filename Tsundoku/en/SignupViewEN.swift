//
//  SignupViewEN.swift
//  Tsundoku
//

import SwiftUI

struct SignupViewEN: View {
    let authStore: AuthStore
    let onBack: () -> Void
    let onComplete: () -> Void

    var body: some View {
        SignupCardView(
            authStore: authStore,
            copy: .english,
            onBack: onBack,
            onComplete: onComplete
        )
    }
}

#Preview {
    SignupViewEN(authStore: AuthStore(), onBack: {}, onComplete: {})
}
