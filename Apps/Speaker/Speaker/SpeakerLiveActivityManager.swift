import ActivityKit
import Foundation
import StereoSyncCore

@MainActor
final class SpeakerLiveActivityManager {
    private var activity: Activity<SpeakerActivityAttributes>?

    func update(phase: SpeakerSessionController.Phase) {
        guard let status = SpeakerActivityStatus.from(phase: phase) else {
            end()
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let content = ActivityContent(
            state: SpeakerActivityAttributes.ContentState(status: status),
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

    func end() {
        guard let activity else { return }
        self.activity = nil
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
