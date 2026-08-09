import Foundation

/// Holds received PCM briefly so Wi‑Fi jitter does not turn into audible gaps.
@MainActor
public final class AudioJitterBuffer {
    public struct Chunk {
        public let header: AudioChunkHeader
        public let pcm: Data
    }

    private let targetDuration: TimeInterval
    private let sampleRate: Double
    private var pending: [UInt64: Chunk] = [:]
    private var nextSequence: UInt64 = 0
    private var bufferedSamples = 0
    private var started = false

    public init(sampleRate: Double, targetDuration: TimeInterval = 0.8) {
        self.sampleRate = sampleRate
        self.targetDuration = targetDuration
    }

    public func reset() {
        pending.removeAll()
        nextSequence = 0
        bufferedSamples = 0
        started = false
    }

    /// Returns contiguous chunks once enough audio is buffered to start safely.
    /// Mid-session joiners often see high sequence numbers — we anchor to the
    /// earliest buffered sequence instead of waiting forever for sequence 0.
    public func append(header: AudioChunkHeader, pcm: Data) -> [Chunk] {
        guard pending[header.sequence] == nil else { return [] }
        if started && header.sequence < nextSequence { return [] }

        pending[header.sequence] = Chunk(header: header, pcm: pcm)
        bufferedSamples += Int(header.sampleCount)

        if !started {
            started = Double(bufferedSamples) / sampleRate >= targetDuration
            if started, let minSeq = pending.keys.min() {
                nextSequence = minSeq
            }
        }
        guard started else { return [] }

        var ready: [Chunk] = []
        while let chunk = pending.removeValue(forKey: nextSequence) {
            bufferedSamples -= Int(chunk.header.sampleCount)
            ready.append(chunk)
            nextSequence += 1
        }
        return ready
    }
}
