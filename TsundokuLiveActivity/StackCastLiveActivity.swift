import ActivityKit
import Foundation
import ThinkingOrbsKit
import SwiftUI
import WidgetKit

struct StackCastLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CastPlaybackActivityAttributes.self) { context in
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    activityArtwork

                    VStack(alignment: .leading, spacing: 3) {
                        Text(context.attributes.castTitle)
                            .font(.headline)
                            .lineLimit(2)
                        Text(context.state.isPlaying ? "再生中" : "一時停止中")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    elapsedView(for: context)
                        .font(.caption2.monospacedDigit())
                        .frame(width: 36, alignment: .leading)

                    GeometryReader { geometry in
                        let progress = min(max(context.state.progress, 0), 1)

                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(.white.opacity(0.22))
                            Capsule()
                                .fill(.white)
                                .frame(width: geometry.size.width * progress)
                        }
                    }
                    .frame(height: 10)

                    Text(context.state.durationLabel)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 36, alignment: .trailing)
                }

                HStack(spacing: 34) {
                    Button(intent: SeekCastBackwardIntent()) {
                        Image(systemName: "gobackward.10")
                            .font(.system(size: 24, weight: .bold))
                    }

                    Button(intent: ToggleCastPlaybackIntent()) {
                        Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 30, weight: .bold))
                            .frame(width: 46, height: 34)
                    }

                    Button(intent: SeekCastForwardIntent()) {
                        Image(systemName: "goforward.10")
                            .font(.system(size: 24, weight: .bold))
                    }
                }
                .foregroundStyle(.white)
                .buttonStyle(.plain)
            }
            .padding(16)
            .lockScreenGlassSurface()
            .activityBackgroundTint(.clear)
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.indigo, .purple.opacity(0.85)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )

                        Image(systemName: "waveform")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 48, height: 48)
                    .padding(.leading, 8)
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.castTitle)
                            .font(.headline)
                            .lineLimit(2)
                        Text(context.state.isPlaying ? "再生中" : "一時停止中")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 6)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 10) {
                        HStack(spacing: 8) {
                            elapsedView(for: context)
                                .font(.caption2.monospacedDigit())
                                .frame(width: 34, alignment: .leading)

                            GeometryReader { geometry in
                                let progress = min(max(context.state.progress, 0), 1)

                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(.white.opacity(0.22))
                                    Capsule()
                                        .fill(.white)
                                        .frame(width: geometry.size.width * progress)
                                }
                            }
                            .frame(height: 10)

                            Text(context.state.durationLabel)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.7))
                                .frame(width: 34, alignment: .trailing)
                        }

                        HStack(spacing: 28) {
                            Button(intent: SeekCastBackwardIntent()) {
                                Image(systemName: "gobackward.10")
                                    .font(.system(size: 22, weight: .bold))
                            }

                            Button(intent: ToggleCastPlaybackIntent()) {
                                Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 26, weight: .bold))
                                    .frame(width: 42, height: 32)
                            }

                            Button(intent: SeekCastForwardIntent()) {
                                Image(systemName: "goforward.10")
                                    .font(.system(size: 22, weight: .bold))
                            }
                        }
                        .foregroundStyle(.white)
                        .buttonStyle(.plain)
                    }
                }
            } compactLeading: {
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.indigo, .purple.opacity(0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Image(systemName: "waveform")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 20, height: 20)
            } compactTrailing: {
                elapsedView(for: context)
                    .font(.caption2.monospacedDigit())
                    .frame(width: 32, alignment: .trailing)
            } minimal: {
                Image(systemName: context.state.isPlaying ? "waveform" : "pause.fill")
                    .foregroundStyle(.white)
            }
            .widgetURL(URL(string: "stashcast://player"))
            .keylineTint(.white)
        }
    }

    private var activityArtwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.indigo, .purple.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Image(systemName: "waveform")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 56, height: 56)
    }

    @ViewBuilder
    private func elapsedView(
        for context: ActivityViewContext<CastPlaybackActivityAttributes>
    ) -> some View {
        if context.state.isPlaying, let startedAt = context.state.startedAt {
            Text(
                timerInterval: startedAt...Date(
                    timeInterval: TimeInterval(context.state.durationSeconds),
                    since: startedAt
                ),
                countsDown: false
            )
        } else {
            Text(context.state.elapsedLabel)
        }
    }

}

struct CastGenerationLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CastGenerationActivityAttributes.self) { context in
            HStack(spacing: 14) {
                ThinkingOrb(state: .working, size: .px64, displaySize: 56)
                    .rotationEffect(.degrees(Double(context.state.animationPhase) * 45))
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.attributes.castTitle)
                        .font(.headline)
                        .lineLimit(2)
                    Text("Castを生成中")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .lockScreenGlassSurface()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ThinkingOrb(state: .working, size: .px20, displaySize: 28)
                        .rotationEffect(.degrees(Double(context.state.animationPhase) * 45))
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.castTitle).font(.headline).lineLimit(1)
                        Text("Castを生成中").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                ThinkingOrb(state: .working, size: .px20, displaySize: 20)
                    .rotationEffect(.degrees(Double(context.state.animationPhase) * 45))
            } compactTrailing: {
                Text("Working...")
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
            } minimal: {
                ThinkingOrb(state: .working, size: .px20, displaySize: 18)
                    .rotationEffect(.degrees(Double(context.state.animationPhase) * 45))
            }
            .keylineTint(.purple)
        }
    }
}

private extension View {
    @ViewBuilder
    func lockScreenGlassSurface() -> some View {
        if #available(iOS 26.0, *) {
            background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.clear)
                    .glassEffect(
                        .regular.tint(.black.opacity(0.08)),
                        in: .rect(cornerRadius: 24)
                    )
            }
        } else {
            background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }
}

@main
struct StackCastLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        StackCastLiveActivity()
        CastGenerationLiveActivity()
    }
}
