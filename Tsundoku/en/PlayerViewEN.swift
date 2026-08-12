//
//  PlayerViewEN.swift
//  Tsundoku
//

import SwiftUI

struct PlayerViewEN: View {
    let authStore: AuthStore
    let castStore: CastStore
    let playbackStore: CastPlaybackStore
    let subscriptionTier: SubscriptionPlanTier
    @Binding var selectedCast: CastRecord?
    @Binding var isDetailPresented: Bool

    var body: some View {
        CastListView(authStore: authStore, castStore: castStore, playbackStore: playbackStore, subscriptionTier: subscriptionTier, language: .english, selectedCast: $selectedCast, isDetailPresented: $isDetailPresented)
    }
}

#Preview {
    PlayerViewEN(authStore: AuthStore(), castStore: CastStore(), playbackStore: CastPlaybackStore(), subscriptionTier: .plus, selectedCast: .constant(nil), isDetailPresented: .constant(false))
}
