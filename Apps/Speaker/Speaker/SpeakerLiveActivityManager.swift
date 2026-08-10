import Foundation
import ChorusCore
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Optional Live Activity bridge. Core speaker sync works without it below iOS 16.2.
@MainActor
final class SpeakerLiveActivityManager {
    func update(
        phase: SpeakerSessionController.Phase,
        sessionTitle: String?,
        hostName: String?,
        roundTripMs: Double?
    ) {
        #if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            LiveActivityController.shared.update(
                phase: phase,
                sessionTitle: sessionTitle,
                hostName: hostName,
                roundTripMs: roundTripMs
            )
        }
        #endif
    }

    func end() {
        #if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            LiveActivityController.shared.end()
        }
        #endif
    }
}

#if canImport(ActivityKit)
@available(iOS 16.2, *)
@MainActor
private final class LiveActivityController {
    static let shared = LiveActivityController()

    private var activity: Activity<SpeakerActivityAttributes>?
    private var lastStatus: SpeakerActivityStatus?
    private var lastSessionTitle: String?
    private var lastHostName: String?
    private var lastRTT: Double?

    func update(
        phase: SpeakerSessionController.Phase,
        sessionTitle: String?,
        hostName: String?,
        roundTripMs: Double?
    ) {
        guard let status = SpeakerActivityStatus.from(phase: phase) else {
            end()
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        lastStatus = status
        lastSessionTitle = sessionTitle
        lastHostName = hostName
        if let roundTripMs {
            lastRTT = roundTripMs
        }
        push()
    }

    func end() {
        guard let activity else { return }
        self.activity = nil
        lastStatus = nil
        lastSessionTitle = nil
        lastHostName = nil
        lastRTT = nil
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func centerTitle(for status: SpeakerActivityStatus) -> String {
        switch status {
        case .playing:
            if let title = lastSessionTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                return title
            }
            return "Chorus"
        case .connected, .waiting:
            if let host = lastHostName?.trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty {
                return host
            }
            return L10n.text(status.localizationKey)
        }
    }

    private func push() {
        guard let status = lastStatus else { return }
        let content = ActivityContent(
            state: SpeakerActivityAttributes.ContentState(
                status: status,
                centerTitle: centerTitle(for: status),
                roundTripMs: lastRTT
            ),
            staleDate: nil
        )
        if let activity {
            Task {
                await activity.update(content)
            }
        } else {
            Task {
                do {
                    activity = try Activity.request(
                        attributes: SpeakerActivityAttributes(),
                        content: content,
                        pushType: nil
                    )
                } catch {
                    // Live Activities are optional; the in-app status remains authoritative.
                }
            }
        }
    }
}
#endif
