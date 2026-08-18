import ActivityKit
import Foundation
import SwiftUI
import WidgetKit

struct StackCastLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CastPlaybackActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: context.state.isPlaying ? "waveform" : "pause.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.castTitle)
                            .font(.headline)
                            .lineLimit(1)
                        Text(context.attributes.subtitle)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    Spacer()

                    elapsedView(for: context)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                }

                ProgressView(value: context.state.progress)
                    .tint(.white)

                HStack {
                    Text(context.state.isPlaying ? "再生中" : "一時停止中")
                    Spacer()
                    Text(context.state.durationLabel)
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
            }
            .padding()
            .activityBackgroundTint(.black)
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

                            ProgressView(value: context.state.progress)
                                .tint(.white)

                            Text(context.state.durationLabel)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.7))
                                .frame(width: 34, alignment: .trailing)
                        }

                        HStack(spacing: 28) {
                            Button(intent: SeekCastBackwardIntent()) {
                                Image(systemName: "gobackward.10")
                                    .font(.title3)
                            }

                            Button(intent: ToggleCastPlaybackIntent()) {
                                Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.title2)
                                    .frame(width: 36, height: 28)
                            }

                            Button(intent: SeekCastForwardIntent()) {
                                Image(systemName: "goforward.10")
                                    .font(.title3)
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

@main
struct StackCastLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        StackCastLiveActivity()
    }
}
