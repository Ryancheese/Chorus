import Foundation

/// Estimates speaker clock offset relative to host using NTP-style exchange.
/// `offset = speakerTime - hostTime`  ⇒  `hostTime ≈ speakerTime - offset`
public struct ClockOffsetEstimate: Sendable {
    public var offset: TimeInterval
    public var roundTrip: TimeInterval
    public var updatedAt: TimeInterval

    public init(offset: TimeInterval, roundTrip: TimeInterval, updatedAt: TimeInterval) {
        self.offset = offset
        self.roundTrip = roundTrip
        self.updatedAt = updatedAt
    }

    /// Convert a host timeline instant into speaker local time.
    public func speakerTime(forHostTime hostTime: TimeInterval) -> TimeInterval {
        hostTime + offset
    }
}

public final class ClockSynchronizer: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [ClockOffsetEstimate] = []
    private let maxSamples: Int

    public init(maxSamples: Int = 8) {
        self.maxSamples = maxSamples
    }

    public var bestEstimate: ClockOffsetEstimate? {
        lock.lock()
        defer { lock.unlock() }
        // Prefer lowest RTT sample (classic NTP heuristic).
        return samples.min(by: { $0.roundTrip < $1.roundTrip })
    }

    public func recordPong(_ pong: ClockPong, hostReceiveTime: TimeInterval) {
        let rtt = hostReceiveTime - pong.hostSendTime
        guard rtt >= 0, rtt < 2.0 else { return }
        // Speaker midpoint of receive/send approximates remote processing time.
        let speakerMid = (pong.speakerReceiveTime + pong.speakerSendTime) / 2
        let hostMid = (pong.hostSendTime + hostReceiveTime) / 2
        let offset = speakerMid - hostMid
        let estimate = ClockOffsetEstimate(offset: offset, roundTrip: rtt, updatedAt: hostReceiveTime)

        lock.lock()
        samples.append(estimate)
        if samples.count > maxSamples {
            samples.removeFirst(samples.count - maxSamples)
        }
        lock.unlock()
    }

    public func reset() {
        lock.lock()
        samples.removeAll()
        lock.unlock()
    }
}

public enum HostTime {
    /// Monotonic-ish wall clock suitable for demo sync (ProcessInfo uptime).
    public static func now() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }
}
