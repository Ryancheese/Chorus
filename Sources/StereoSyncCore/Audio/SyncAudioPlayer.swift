import AVFoundation
import Foundation

/// Schedules Float32 mono PCM on a precise host time using AVAudioEngine.
@MainActor
public final class SyncAudioPlayer: ObservableObject {
    @Published public private(set) var isPlaying = false
    @Published public private(set) var lastError: String?

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var format: AVAudioFormat
    private var started = false
    private var hasScheduledAudio = false

    public init(sampleRate: Double = SyncProtocol.sampleRate) {
        format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    public func prepareSession(sampleRate: Double) throws {
        stop()
        format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!
        engine.disconnectNodeOutput(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        try engine.start()
        started = true
        hasScheduledAudio = false
    }

    /// Schedule PCM to start at an absolute local uptime (ProcessInfo.systemUptime).
    public func schedule(pcm: [Float], playAtLocalUptime: TimeInterval) {
        guard started else { return }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(pcm.count)) else { return }
        buffer.frameLength = AVAudioFrameCount(pcm.count)
        pcm.withUnsafeBufferPointer { src in
            if let dst = buffer.floatChannelData?[0], let base = src.baseAddress {
                dst.update(from: base, count: pcm.count)
            }
        }

        if !player.isPlaying {
            player.play()
        }
        if hasScheduledAudio {
            // Appending to the existing render queue avoids tiny timing gaps at
            // every network chunk boundary, which are audible as ticks/beeps.
            player.scheduleBuffer(buffer, at: nil, options: [])
        } else {
            let now = HostTime.now()
            let delay = max(0, playAtLocalUptime - now)
            let hostTime = machHostTime(afterSeconds: delay)
            player.scheduleBuffer(buffer, at: AVAudioTime(hostTime: hostTime), options: [])
            hasScheduledAudio = true
        }
        isPlaying = true
    }

    public func scheduleChunk(pcmData: Data, playAtLocalUptime: TimeInterval) {
        let count = pcmData.count / MemoryLayout<Float>.size
        let samples: [Float] = pcmData.withUnsafeBytes { raw in
            Array(raw.bindMemory(to: Float.self).prefix(count))
        }
        schedule(pcm: samples, playAtLocalUptime: playAtLocalUptime)
    }

    public func stop() {
        player.stop()
        if started {
            engine.stop()
            engine.reset()
            started = false
        }
        hasScheduledAudio = false
        isPlaying = false
    }

    private func machHostTime(afterSeconds seconds: TimeInterval) -> UInt64 {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        let now = mach_absolute_time()
        let nanos = seconds * 1_000_000_000
        let ticks = nanos * Double(info.denom) / Double(info.numer)
        return now + UInt64(ticks)
    }
}
