import Foundation
import UserNotifications

@MainActor
final class UnplayedCastReminderScheduler {
    static let shared = UnplayedCastReminderScheduler()

    private let notificationIdentifier = "unplayed-cast-reminder"
    private let notifiedCastIDsKey = "stackcast.unplayed-cast-reminder.notified-cast-ids"
    private let reminderInterval: TimeInterval = 24 * 60 * 60
    private let iso8601 = ISO8601DateFormatter()

    private init() {
        iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func reschedule(casts: [CastRecord], playbackStore: CastPlaybackStore, language: AppLanguage) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let hasPendingReminder = requests.contains { $0.identifier == self.notificationIdentifier }
            let legacyIdentifiers = requests
                .map(\.identifier)
                .filter { $0.hasPrefix("unplayed-cast-reminder-") }
            if !legacyIdentifiers.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: legacyIdentifiers)
                center.removeDeliveredNotifications(withIdentifiers: legacyIdentifiers)
            }
            Task { @MainActor in
                self.schedule(
                    casts: casts,
                    playbackStore: playbackStore,
                    language: language,
                    hasPendingReminder: hasPendingReminder
                )
            }
        }
    }

    private func schedule(
        casts: [CastRecord],
        playbackStore: CastPlaybackStore,
        language: AppLanguage,
        hasPendingReminder: Bool
    ) {
        let center = UNUserNotificationCenter.current()
        // Replace the single aggregate reminder instead of creating one
        // request per Cast whenever the Cast list is refreshed.

        let eligibleCasts = casts.filter {
            $0.status == "completed" && $0.audioURL != nil && playbackStore.isUnplayed($0)
        }
        let currentCastIDs = Set(casts.map(\.id))
        var notifiedCastIDs = Set(UserDefaults.standard.stringArray(forKey: notifiedCastIDsKey) ?? [])
        notifiedCastIDs.formIntersection(currentCastIDs)
        UserDefaults.standard.set(Array(notifiedCastIDs), forKey: notifiedCastIDsKey)

        let unnotifiedCasts = eligibleCasts.filter { !notifiedCastIDs.contains($0.id) }
        guard !unnotifiedCasts.isEmpty else {
            if eligibleCasts.isEmpty && hasPendingReminder {
                center.removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
            }
            return
        }

        let now = Date()
        let dueCasts = unnotifiedCasts.filter {
            guard let generatedAt = generatedDate(for: $0) else { return false }
            return now.timeIntervalSince(generatedAt) >= reminderInterval
        }
        let targetCast = (dueCasts.isEmpty ? unnotifiedCasts : dueCasts)
            .sorted { $0.createdAt < $1.createdAt }
            .first
        guard let targetCast, let generatedAt = generatedDate(for: targetCast) else { return }

        // If several Casts are already overdue, this one notification covers
        // the whole overdue group so the user is not interrupted repeatedly.
        let IDsToMark = dueCasts.isEmpty ? [targetCast.id] : dueCasts.map(\.id)
        notifiedCastIDs.formUnion(IDsToMark)
        UserDefaults.standard.set(Array(notifiedCastIDs), forKey: notifiedCastIDsKey)

        let secondsUntilReminder = max(1, reminderInterval - now.timeIntervalSince(generatedAt))
        let content = UNMutableNotificationContent()
        content.title = language == .english ? "You have unplayed Casts" : "未再生のCastが残っています"
        content.body = language == .english
            ? "Tap to listen to your Cast."
            : "タップしてCastを聴いてみましょう。"
        content.sound = .default
        content.userInfo = ["deepLink": "stashcast://cast-detail/\(targetCast.id)"]

        let request = UNNotificationRequest(
            identifier: notificationIdentifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: secondsUntilReminder, repeats: false)
        )
        center.add(request) { error in
            if let error { print("[notifications] failed to schedule unplayed Cast reminder: \(error.localizedDescription)") }
        }
    }

    private func generatedDate(for cast: CastRecord) -> Date? {
        if let completedAt = cast.completedAt, let date = iso8601.date(from: completedAt) { return date }
        return iso8601.date(from: cast.createdAt)
    }
}
