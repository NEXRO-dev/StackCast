//
//  CastPlaybackStore.swift
//  Tsundoku
//

import AVFoundation
import Observation
import SwiftUI

let castPlaybackRateKey = "castPlaybackRate"

@MainActor
@Observable
final class CastPlaybackStore {
    private(set) var currentCast: CastRecord?
    private(set) var isPlaying = false
    private(set) var hasStartedPlayback = false
    private(set) var progress = 0.0
    private(set) var elapsedTime = "0:00"
    private(set) var durationTime = "0:00"
    private(set) var playbackRate: Double

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    init() {
        playbackRate = UserDefaults.standard.object(forKey: castPlaybackRateKey) as? Double ?? 1.0
    }

    func toggle(_ cast: CastRecord, subscriptionTier: SubscriptionPlanTier) {
        if currentCast?.id == cast.id, isPlaying {
            pause()
        } else {
            play(cast, subscriptionTier: subscriptionTier)
        }
    }

    func play(_ cast: CastRecord, subscriptionTier: SubscriptionPlanTier) {
        guard let audioURL = cast.audioURL else { return }

        if currentCast?.id == cast.id, player != nil {
            activateAudioSession()
            player?.playImmediately(atRate: Float(playbackRate))
            isPlaying = true
            hasStartedPlayback = true
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
        isPlaying = false
    }

    func seek(by seconds: Double, in cast: CastRecord) {
        guard let player = prepareForSeeking(cast) else { return }
        let duration = effectiveDuration(for: cast, player: player)
        let playerTime = player.currentTime().seconds
        let current = playerTime.isFinite ? playerTime : progress * duration

        let target = min(max(current + seconds, 0), duration)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        updateDisplayedPosition(target, duration: duration)
    }

    func seek(toProgress requestedProgress: Double, in cast: CastRecord) {
        guard let player = prepareForSeeking(cast) else { return }
        let duration = effectiveDuration(for: cast, player: player)
        let target = min(max(requestedProgress, 0), 1) * duration
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        updateDisplayedPosition(target, duration: duration)
    }

    func stop() {
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
                self.elapsedTime = self.formatTime(Int(current))
                self.durationTime = self.formatTime(Int(total))
            }
        }
    }

    private func prepareForSeeking(_ cast: CastRecord) -> AVPlayer? {
        if currentCast?.id == cast.id, let player {
            return player
        }

        guard let audioURL = cast.audioURL else { return nil }
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

    private func updateDisplayedPosition(_ seconds: Double, duration: Double) {
        progress = min(max(seconds / duration, 0), 1)
        elapsedTime = formatTime(Int(seconds))
        durationTime = formatTime(Int(duration))
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

    private func formatTime(_ seconds: Int) -> String {
        let safeSeconds = max(seconds, 0)
        return "\(safeSeconds / 60):\(String(format: "%02d", safeSeconds % 60))"
    }
}
