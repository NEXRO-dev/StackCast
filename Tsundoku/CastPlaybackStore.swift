//
//  CastPlaybackStore.swift
//  Tsundoku
//

import AVFoundation
import ActivityKit
import Observation
import OSLog
import SwiftUI

nonisolated func playbackCommandNotificationCallback(
    _: CFNotificationCenter?,
    observer: UnsafeMutableRawPointer?,
    _: CFNotificationName?,
    _: UnsafeRawPointer?,
    _: CFDictionary?
) {
    guard let observer else { return }
    let store = Unmanaged<CastPlaybackStore>.fromOpaque(observer).takeUnretainedValue()
    Task { @MainActor in
        store.consumePlaybackCommand()
    }
}

let castPlaybackRateKey = "castPlaybackRate"

private enum CastPlaybackProgressStorage {
    private static let key = "castPlaybackProgress"

    static func load() -> [String: Double] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let progress = try? JSONDecoder().decode([String: Double].self, from: data) else {
            return [:]
        }
        return progress
    }

    static func save(_ progress: [String: Double]) {
        guard let data = try? JSONEncoder().encode(progress) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

@MainActor
@Observable
final class CastPlaybackStore {
    static let shared = CastPlaybackStore()

    private let logger = Logger(subsystem: "com.nexro.Tsundoku", category: "LiveActivity")
    private(set) var currentCast: CastRecord?
    private(set) var isPlaying = false
    private(set) var hasStartedPlayback = false
    private(set) var progress = 0.0
    private(set) var elapsedTime = "0:00"
    private(set) var durationTime = "0:00"
    private(set) var playbackRate: Double
    private(set) var progressRevision = 0

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var liveActivity: Activity<CastPlaybackActivityAttributes>?
    private var commandPollTask: Task<Void, Never>?
    private var lastCommandID: String?
    private var lastLiveActivityUpdate = Date.distantPast
    private var savedProgress: [String: Double]
    private var lastPersistedPlaybackSecond = -1.0

    init() {
        playbackRate = UserDefaults.standard.object(forKey: castPlaybackRateKey) as? Double ?? 1.0
        savedProgress = CastPlaybackProgressStorage.load()
        lastCommandID = UserDefaults(suiteName: PlaybackCommandBridge.suiteName)?
            .string(forKey: PlaybackCommandBridge.commandIDKey)
        commandPollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.consumePlaybackCommand()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            playbackCommandNotificationCallback,
            PlaybackCommandBridge.notificationName as CFString,
            nil,
            .deliverImmediately
        )

        PlaybackCommandRouter.handler = { [weak self] command in
            self?.executePlaybackCommand(command)
        }
        logger.info("Live Activity playback command handler registered")
    }

    func toggle(_ cast: CastRecord, subscriptionTier: SubscriptionPlanTier) {
        if currentCast?.id == cast.id, isPlaying {
            pause()
        } else {
            play(cast, subscriptionTier: subscriptionTier)
        }
    }

    func toggleCurrent(subscriptionTier: SubscriptionPlanTier) {
        guard let currentCast else { return }
        toggle(currentCast, subscriptionTier: subscriptionTier)
    }

    func seekCurrent(by seconds: Double) {
        guard let currentCast else { return }
        seek(by: seconds, in: currentCast)
    }

    func play(_ cast: CastRecord, subscriptionTier: SubscriptionPlanTier) {
        guard let audioURL = playbackURL(for: cast) else { return }

        if currentCast?.id == cast.id, player != nil {
            activateAudioSession()
            player?.playImmediately(atRate: Float(playbackRate))
            isPlaying = true
            hasStartedPlayback = true
            updateLiveActivity(force: true)
            return
        }

        stop()
        activateAudioSession()

        let item = AVPlayerItem(url: audioURL)
        let nextPlayer = AVPlayer(playerItem: item)
        player = nextPlayer
        currentCast = cast
        progress = 0
        elapsedTime = "0:00"
        durationTime = formatTime(cast.durationMinutes * 60)
        observe(item: item, player: nextPlayer)
        nextPlayer.playImmediately(atRate: Float(playbackRate))
        isPlaying = true
        hasStartedPlayback = true
        startLiveActivity(for: cast, subscriptionTier: subscriptionTier)
    }

    func setPlaybackRate(_ rate: Double) {
        playbackRate = rate
        UserDefaults.standard.set(rate, forKey: castPlaybackRateKey)
        guard let player else { return }
        if isPlaying {
            player.playImmediately(atRate: Float(rate))
        } else {
            player.rate = Float(rate)
        }
    }

    func pause() {
        player?.pause()
        persistCurrentProgress(force: true)
        isPlaying = false
        updateLiveActivity(force: true)
    }

    func seek(by seconds: Double, in cast: CastRecord) {
        guard let player = prepareForSeeking(cast) else { return }
        let duration = effectiveDuration(for: cast, player: player)
        let playerTime = player.currentTime().seconds
        let current = playerTime.isFinite ? playerTime : progress * duration

        let target = min(max(current + seconds, 0), duration)
        updateDisplayedPosition(target, duration: duration)
        updateLiveActivity(force: true, elapsedOverride: target)
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    func seek(toProgress requestedProgress: Double, in cast: CastRecord) {
        guard let player = prepareForSeeking(cast) else { return }
        let duration = effectiveDuration(for: cast, player: player)
        let target = min(max(requestedProgress, 0), 1) * duration
        updateDisplayedPosition(target, duration: duration)
        updateLiveActivity(force: true, elapsedOverride: target)
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    func isUnplayed(_ cast: CastRecord) -> Bool {
        _ = progressRevision
        let storedProgress = savedProgress[cast.id] ?? 0
        if currentCast?.id == cast.id {
            return max(storedProgress, progress) <= 0.001
        }
        return storedProgress <= 0.001
    }

    func stop() {
        persistCurrentProgress(force: true)
        player?.pause()
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        player = nil
        timeObserver = nil
        endObserver = nil
        currentCast = nil
        isPlaying = false
        hasStartedPlayback = false
        progress = 0
        elapsedTime = "0:00"
        durationTime = "0:00"
        deactivateAudioSession()
        endLiveActivity()
    }

    func handleScenePhase(_ phase: ScenePhase, subscriptionTier: SubscriptionPlanTier) {
        guard subscriptionTier == .free, phase == .background else { return }
        pause()
        deactivateAudioSession()
    }

    private func observe(item: AVPlayerItem, player: AVPlayer) {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.player === player else { return }
                self.isPlaying = false
                self.progress = 1
                self.persistCurrentProgress(force: true)
                self.updateLiveActivity(force: true)
                AppReviewRequest.recordCompletedCastPlayback()
            }
        }

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let current = time.seconds
                let total = item.duration.seconds
                guard current.isFinite, total.isFinite, total > 0 else { return }
                self.progress = min(max(current / total, 0), 1)
                self.persistProgressIfNeeded(currentSeconds: current, force: false)
                self.elapsedTime = self.formatTime(Int(current))
                self.updateLiveActivity()
                self.durationTime = self.formatTime(Int(total))
            }
        }
    }

    private func prepareForSeeking(_ cast: CastRecord) -> AVPlayer? {
        if currentCast?.id == cast.id, let player {
            return player
        }

        guard let audioURL = playbackURL(for: cast) else { return nil }
        stop()

        let item = AVPlayerItem(url: audioURL)
        let nextPlayer = AVPlayer(playerItem: item)
        player = nextPlayer
        currentCast = cast
        progress = 0
        elapsedTime = "0:00"
        durationTime = formatTime(cast.durationMinutes * 60)
        observe(item: item, player: nextPlayer)
        return nextPlayer
    }

    private func effectiveDuration(for cast: CastRecord, player: AVPlayer) -> Double {
        let loadedDuration = player.currentItem?.duration.seconds ?? 0
        if loadedDuration.isFinite, loadedDuration > 0 {
            return loadedDuration
        }
        return Double(max(cast.durationMinutes * 60, 1))
    }

    private func playbackURL(for cast: CastRecord) -> URL? {
        CastDownloadStore.shared.audioURL(for: cast) ?? cast.audioURL
    }

    private func updateDisplayedPosition(_ seconds: Double, duration: Double) {
        progress = min(max(seconds / duration, 0), 1)
        persistCurrentProgress(force: true)
        elapsedTime = formatTime(Int(seconds))
        durationTime = formatTime(Int(duration))
    }

    private func persistProgressIfNeeded(currentSeconds: Double, force: Bool) {
        guard let castID = currentCast?.id else { return }
        guard force
            || (currentSeconds >= 1
                && (lastPersistedPlaybackSecond < 0 || currentSeconds - lastPersistedPlaybackSecond >= 5))
            || progress >= 1 else { return }

        let normalizedProgress = min(max(progress, 0), 1)
        guard savedProgress[castID] != normalizedProgress else { return }
        savedProgress[castID] = normalizedProgress
        lastPersistedPlaybackSecond = currentSeconds
        progressRevision += 1
        CastPlaybackProgressStorage.save(savedProgress)
    }

    private func persistCurrentProgress(force: Bool) {
        guard currentCast != nil else { return }
        let currentSeconds = player?.currentTime().seconds ?? progress * 60
        persistProgressIfNeeded(currentSeconds: currentSeconds, force: force)
    }

    private func activateAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.allowAirPlay])
            try session.setActive(true)
        } catch {
            // Foreground playback can still work if another app owns the audio session.
        }
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    fileprivate func consumePlaybackCommand() {
        guard let defaults = UserDefaults(suiteName: PlaybackCommandBridge.suiteName) else { return }
        guard let commandID = defaults.string(forKey: PlaybackCommandBridge.commandIDKey),
              commandID != lastCommandID else { return }
        lastCommandID = commandID

        guard let command = defaults.string(forKey: PlaybackCommandBridge.commandKey) else { return }
        executePlaybackCommand(command)
    }

    private func executePlaybackCommand(_ command: String) {
        logger.info("Executing Live Activity playback command: \(command, privacy: .public)")
        guard currentCast != nil else {
            logger.error("Ignored Live Activity playback command because there is no current Cast")
            return
        }

        if command == "toggle" {
            toggleCurrent(subscriptionTier: .plus)
        } else if command.hasPrefix("seek:"),
                  let seconds = Double(command.dropFirst("seek:".count)) {
            seekCurrent(by: seconds)
        }
    }

    private func startLiveActivity(for cast: CastRecord, subscriptionTier: SubscriptionPlanTier) {
        guard subscriptionTier != .free else {
            logger.debug("Live Activity skipped for free plan")
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            logger.error("Live Activities are disabled")
            return
        }

        let attributes = CastPlaybackActivityAttributes(
            castTitle: cast.title,
            subtitle: "StackCast"
        )
        let state = currentActivityState()

        Task {
            do {
                liveActivity = try Activity.request(
                    attributes: attributes,
                    content: ActivityContent(state: state, staleDate: nil),
                    pushType: nil
                )
            } catch {
                // Live Activity is supplementary UI; playback must continue if it cannot start.
                logger.error("Live Activity request failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func updateLiveActivity(force: Bool = false, elapsedOverride: Double? = nil) {
        guard liveActivity != nil else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastLiveActivityUpdate) >= 0.8 else { return }
        lastLiveActivityUpdate = now
        let state = currentActivityState(elapsedOverride: elapsedOverride)

        Task {
            await liveActivity?.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    private func endLiveActivity() {
        guard let liveActivity else { return }
        let finalState = currentActivityState()

        Task {
            await liveActivity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .immediate
            )
        }
        self.liveActivity = nil
    }

    private func currentActivityState(
        elapsedOverride: Double? = nil
    ) -> CastPlaybackActivityAttributes.ContentState {
        let rawSeconds = player?.currentTime().seconds ?? 0
        let rawDuration = player?.currentItem?.duration.seconds ?? 0
        let resolvedSeconds = elapsedOverride ?? rawSeconds
        let elapsed = resolvedSeconds.isFinite ? max(Int(resolvedSeconds), 0) : 0
        let total = rawDuration.isFinite && rawDuration > 0
            ? max(Int(rawDuration), 1)
            : max(Int(currentCast?.durationMinutes ?? 0) * 60, 1)
        let startedAt = isPlaying
            ? Date(timeIntervalSinceNow: -Double(elapsed))
            : nil

        return .init(
            isPlaying: isPlaying,
            elapsedSeconds: elapsed,
            durationSeconds: total,
            progress: min(max(Double(elapsed) / Double(total), 0), 1),
            startedAt: startedAt
        )
    }

    private func formatTime(_ seconds: Int) -> String {
        let safeSeconds = max(seconds, 0)
        return "\(safeSeconds / 60):\(String(format: "%02d", safeSeconds % 60))"
    }
}
