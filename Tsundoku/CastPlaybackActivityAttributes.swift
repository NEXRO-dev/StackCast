//
//  CastPlaybackActivityAttributes.swift
//  Shared by the app and the Live Activity extension.
//

import ActivityKit
import Foundation

struct CastPlaybackActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var isPlaying: Bool
        var elapsedSeconds: Int
        var durationSeconds: Int
        var progress: Double
        var startedAt: Date?

        var elapsedLabel: String {
            formatTime(elapsedSeconds)
        }

        var durationLabel: String {
            formatTime(durationSeconds)
        }

        private func formatTime(_ seconds: Int) -> String {
            let safeSeconds = max(seconds, 0)
            return "\(safeSeconds / 60):\(String(format: "%02d", safeSeconds % 60))"
        }
    }

    var castTitle: String
    var subtitle: String
}

struct CastGenerationActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var status: String
        var progressPercent: Int = 0
        var isCompleted: Bool = false
    }

    var castTitle: String
    var subtitle: String
}
