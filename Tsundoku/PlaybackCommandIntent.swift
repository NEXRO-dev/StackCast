import AppIntents
import Foundation
import OSLog

enum PlaybackCommandBridge {
    private static let logger = Logger(subsystem: "com.nexro.Tsundoku", category: "LiveActivityIntent")
    nonisolated static let suiteName = "group.com.nexro.Tsundoku"
    nonisolated static let commandKey = "liveActivity.playbackCommand"
    nonisolated static let commandIDKey = "liveActivity.playbackCommand.id"
    nonisolated static let notificationName = "com.nexro.Tsundoku.playbackCommand"

    nonisolated static func postNotification() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(notificationName as CFString),
            nil,
            nil,
            true
        )
    }

    static func dispatch(_ command: String) async {
        let handledDirectly = await MainActor.run {
            guard let handler = PlaybackCommandRouter.handler else { return false }
            handler(command)
            return true
        }
        if handledDirectly {
            logger.info("Dispatched playback command directly: \(command, privacy: .public)")
            return
        }

        logger.error("Playback handler unavailable; persisting command for fallback delivery: \(command, privacy: .public)")
        let defaults = UserDefaults(suiteName: suiteName)
        defaults?.set(command, forKey: commandKey)
        defaults?.set(UUID().uuidString, forKey: commandIDKey)
        postNotification()
    }
}

@MainActor
enum PlaybackCommandRouter {
    static var handler: ((String) -> Void)?
}

struct ToggleCastPlaybackIntent: AppIntent, LiveActivityIntent, AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Play or pause StackCast"
    static var openAppWhenRun: Bool = false
    static var supportedModes: IntentModes = .background

    init() {}

    func perform() async throws -> some IntentResult {
        await PlaybackCommandBridge.dispatch("toggle")
        return .result()
    }
}

struct SeekCastBackwardIntent: AppIntent, LiveActivityIntent, AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Skip StackCast backward 10 seconds"
    static var openAppWhenRun: Bool = false
    static var supportedModes: IntentModes = .background

    init() {}

    func perform() async throws -> some IntentResult {
        await PlaybackCommandBridge.dispatch("seek:-10")
        return .result()
    }
}

struct SeekCastForwardIntent: AppIntent, LiveActivityIntent, AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Skip StackCast forward 10 seconds"
    static var openAppWhenRun: Bool = false
    static var supportedModes: IntentModes = .background

    init() {}

    func perform() async throws -> some IntentResult {
        await PlaybackCommandBridge.dispatch("seek:10")
        return .result()
    }
}
