import Foundation
import UserNotifications

@MainActor
final class UnplayedCastReminderScheduler {
    static let shared = UnplayedCastReminderScheduler()

    private let notificationPrefix = "unplayed-cast-reminder-"
    private let reminderInterval: TimeInterval = 24 * 60 * 60
    private let iso8601 = ISO8601DateFormatter()

    private init() {
        iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func reschedule(casts: [CastRecord], playbackStore: CastPlaybackStore, language: AppLanguage) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: casts.map { notificationPrefix + $0.id })

        for cast in casts where cast.status == "completed" && cast.audioURL != nil && playbackStore.isUnplayed(cast) {
            guard let generatedAt = generatedDate(for: cast) else { continue }
            let secondsUntilReminder = max(1, reminderInterval - Date().timeIntervalSince(generatedAt))
            let content = UNMutableNotificationContent()
            content.title = language == .english ? "You have an unplayed Cast" : "未再生のCastが残っています"
            content.body = language == .english ? "Tap to listen to your Cast." : "タップしてCastを聴いてみましょう。"
            content.sound = .default
            content.userInfo = ["deepLink": "stashcast://cast-detail/\(cast.id)"]

            let request = UNNotificationRequest(
                identifier: notificationPrefix + cast.id,
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: secondsUntilReminder, repeats: false)
            )
            center.add(request) { error in
                if let error { print("[notifications] failed to schedule unplayed Cast reminder: \(error.localizedDescription)") }
            }
        }
    }

    private func generatedDate(for cast: CastRecord) -> Date? {
        if let completedAt = cast.completedAt, let date = iso8601.date(from: completedAt) { return date }
        return iso8601.date(from: cast.createdAt)
    }
}
