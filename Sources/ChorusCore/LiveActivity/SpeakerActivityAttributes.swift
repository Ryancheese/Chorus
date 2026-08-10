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

    public var systemImage: String {
        switch self {
        case .waiting: "wifi"
        case .connected: "checkmark.circle.fill"
        case .playing: "play.fill"
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

@available(iOS 16.2, *)
public struct SpeakerActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var status: SpeakerActivityStatus
        /// Playing track, or connected computer name when idle/connected.
        public var centerTitle: String
        /// Round-trip latency in milliseconds (nil until calibrated).
        public var roundTripMs: Double?

        public init(
            status: SpeakerActivityStatus,
            centerTitle: String,
            roundTripMs: Double? = nil
        ) {
            self.status = status
            self.centerTitle = centerTitle
            self.roundTripMs = roundTripMs
        }
    }

    public init() {}
}
#endif
