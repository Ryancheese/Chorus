import Foundation

/// Selects a conservative start lead from recent round-trip observations.
public struct AdaptiveLeadTime: Sendable {
    private var roundTrips: [TimeInterval] = []
    private let maximumSamples = 20

    public init() {}

    public mutating func record(roundTrip: TimeInterval) {
        guard roundTrip >= 0, roundTrip < 2 else { return }
        roundTrips.append(roundTrip)
        if roundTrips.count > maximumSamples {
            roundTrips.removeFirst(roundTrips.count - maximumSamples)
        }
    }

    /// 1.2–1.5 seconds prioritises continuous playback over immediate start.
    public var recommendedLeadTime: TimeInterval {
        guard !roundTrips.isEmpty else { return SyncProtocol.defaultLeadTime }
        let sorted = roundTrips.sorted()
        let p90 = sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * 0.9))]
        return min(max(1.2, 1.0 + (2 * p90)), 1.5)
    }
}
