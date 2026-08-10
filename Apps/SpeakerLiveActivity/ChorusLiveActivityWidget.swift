import ActivityKit
import ChorusCore
import SwiftUI
import WidgetKit

@main
struct ChorusLiveActivityWidgetBundle: WidgetBundle {
    var body: some Widget {
        ChorusLiveActivityWidget()
    }
}

struct ChorusLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SpeakerActivityAttributes.self) { context in
            // Lock-screen / banner: left status · center title · right RTT
            HStack(spacing: 12) {
                statusChip(context.state.status)
                Text(context.state.centerTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                rttBadge(context.state.roundTripMs)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .activityBackgroundTint(.black.opacity(0.82))
            .activitySystemActionForegroundColor(.white)
            .widgetURL(URL(string: "chorus://speaker"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    statusChip(context.state.status)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.centerTitle)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    rttBadge(context.state.roundTripMs)
                        .padding(.trailing, 6)
                }
            } compactLeading: {
                Image(systemName: context.state.status.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.cyan)
            } compactTrailing: {
                rttCompact(context.state.roundTripMs)
            } minimal: {
                Image(systemName: context.state.status.systemImage)
                    .foregroundStyle(.cyan)
            }
            .widgetURL(URL(string: "chorus://speaker"))
            .keylineTint(.cyan)
        }
    }

    private func statusChip(_ status: SpeakerActivityStatus) -> some View {
        HStack(spacing: 6) {
            Image(systemName: status.systemImage)
                .font(.system(size: 12, weight: .bold))
            Text(L10n.text(status.localizationKey))
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.cyan)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.cyan.opacity(0.14), in: Capsule())
    }

    private func rttBadge(_ ms: Double?) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text("RTT")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(rttText(ms))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.cyan)
                .monospacedDigit()
        }
        .accessibilityLabel(rttAccessibility(ms))
    }

    private func rttCompact(_ ms: Double?) -> some View {
        Text(rttText(ms))
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.cyan)
            .monospacedDigit()
            .accessibilityLabel(rttAccessibility(ms))
    }

    private func rttText(_ ms: Double?) -> String {
        guard let ms else { return "—" }
        return String(format: "%.0fms", ms)
    }

    private func rttAccessibility(_ ms: Double?) -> String {
        guard let ms else { return "RTT unavailable" }
        return String(format: "RTT %.0f milliseconds", ms)
    }
}
