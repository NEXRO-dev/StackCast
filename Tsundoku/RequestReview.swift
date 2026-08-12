//
//  RequestReview.swift
//  Tsundoku
//

import SwiftUI
import StoreKit
import UIKit

@MainActor
enum AppReviewRequest {
    private static let completedCastPlayCountKey = "completedCastPlayCount"
    private static let lastReviewRequestMilestoneKey = "lastReviewRequestMilestone"
    private static let milestones = [1, 5, 10]

    static func recordCompletedCastPlayback(
        defaults: UserDefaults = .standard
    ) {
        let completedCount = defaults.integer(forKey: completedCastPlayCountKey) + 1
        defaults.set(completedCount, forKey: completedCastPlayCountKey)

        let lastMilestone = defaults.integer(forKey: lastReviewRequestMilestoneKey)
        guard let milestone = milestones.last(where: { completedCount >= $0 }),
              milestone > lastMilestone else { return }

        defaults.set(milestone, forKey: lastReviewRequestMilestoneKey)
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }

        AppStore.requestReview(in: scene)
    }
}

#Preview("Review Request Rules") {
    VStack(spacing: 12) {
        Image(systemName: "star.bubble.fill")
            .font(.system(size: 42))
            .foregroundStyle(.yellow)
        Text("Review request is triggered after Cast playback milestones.")
            .multilineTextAlignment(.center)
    }
    .padding(32)
}
