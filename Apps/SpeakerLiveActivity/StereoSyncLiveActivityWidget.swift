import ActivityKit
import StereoSyncCore
import SwiftUI
import WidgetKit

@main
struct StereoSyncLiveActivityWidgetBundle: WidgetBundle {
    var body: some Widget {
        StereoSyncLiveActivityWidget()
    }
}

struct StereoSyncLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SpeakerActivityAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: "hifispeaker.fill")
                    .foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text("StereoSync")
                        .font(.headline)
                    Text(L10n.text(context.state.status.localizationKey))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: symbol(for: context.state.status))
                    .foregroundStyle(.cyan)
            }
            .padding(.horizontal)
            .activityBackgroundTint(.black.opacity(0.8))
            .activitySystemActionForegroundColor(.white)
            .widgetURL(URL(string: "stereosync://speaker"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "hifispeaker.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.cyan)
                        .frame(width: 30, height: 30)
                        .background(.cyan.opacity(0.14), in: Circle())
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: symbol(for: context.state.status))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.cyan)
                        .frame(width: 30, height: 30)
                        .background(.cyan.opacity(0.14), in: Circle())
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 10) {
                        Image(systemName: symbol(for: context.state.status))
                            .foregroundStyle(.cyan)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(context.state.contentTitle ?? "StereoSync")
                                .font(.headline)
                                .lineLimit(1)
                            Text(L10n.text(context.state.status.localizationKey))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                }
            } compactLeading: {
                Image(systemName: "hifispeaker.fill")
            } compactTrailing: {
                Image(systemName: symbol(for: context.state.status))
            } minimal: {
                Image(systemName: "hifispeaker.fill")
            }
            .widgetURL(URL(string: "stereosync://speaker"))
            .keylineTint(.cyan)
        }
    }

    private func symbol(for status: SpeakerActivityStatus) -> String {
        switch status {
        case .waiting: "wifi"
        case .connected: "checkmark.circle.fill"
        case .playing: "speaker.wave.3.fill"
        }
    }
}
