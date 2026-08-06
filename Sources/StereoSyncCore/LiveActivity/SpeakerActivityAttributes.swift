import Foundation

public enum SpeakerActivityStatus: String, Codable, Hashable, Sendable {
    case waiting
    case connected
    case playing

    public var localizationKey: String {
        switch self {
        case .waiting: "activity.waiting"
        case .connected: "activity.connected"
        case .playing: "activity.playing"
        }
    }

    public static func from(phase: SpeakerSessionController.Phase) -> Self? {
        switch phase {
        case .idle, .error:
            nil
        case .advertising, .connecting, .syncing:
            .waiting
        case .connected, .ready:
            .connected
        case .playing:
            .playing
        }
    }
}

#if os(iOS)
import ActivityKit

@available(iOS 16.1, *)
public struct SpeakerActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var status: SpeakerActivityStatus

        public init(status: SpeakerActivityStatus) {
            self.status = status
        }
    }

    public init() {}
}
#endif
