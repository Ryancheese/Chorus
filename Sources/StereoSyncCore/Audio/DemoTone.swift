import Foundation

public enum DemoTone {
    /// Generates a short A4 sine tone for first-run testing without a music file.
    public static func makeTrack(
        frequency: Double = 440,
        duration: TimeInterval = 4,
        sampleRate: Double = SyncProtocol.sampleRate,
        title: String = "Demo Tone A4"
    ) -> DecodedTrack {
        let count = Int(duration * sampleRate)
        var samples = [Float](repeating: 0, count: count)
        let twoPiF = 2 * Double.pi * frequency
        for i in 0..<count {
            let t = Double(i) / sampleRate
            let envelope = min(1, Double(i) / (sampleRate * 0.02)) * min(1, Double(count - i) / (sampleRate * 0.05))
            samples[i] = Float(sin(twoPiF * t) * 0.35 * envelope)
        }
        return DecodedTrack(title: title, sampleRate: sampleRate, channelCount: 1, pcmFloat32Mono: samples)
    }
}
