import Foundation

/// Free Host may keep one Speaker; Pro unlocks unlimited concurrent Speakers.
public enum SpeakerConnectionPolicy {
    public static let freeSpeakerLimit = 1

    public static func allowsConnection(currentCount: Int, isPro: Bool) -> Bool {
        isPro || currentCount < freeSpeakerLimit
    }

    public static func remainingFreeSlots(currentCount: Int, isPro: Bool) -> Int {
        if isPro { return .max }
        return max(0, freeSpeakerLimit - currentCount)
    }
}
