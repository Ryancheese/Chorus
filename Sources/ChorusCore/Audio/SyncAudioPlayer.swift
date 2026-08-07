import AVFoundation
import Foundation
#if os(macOS)
import AudioToolbox
import CoreAudio
#endif

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
    /// Bumped on every prepare/stop so a stale async `setActive(false)` cannot
    /// deactivate a newer playback session (that race = silent “播放中”).
    private var sessionEpoch: UInt64 = 0

    public init(sampleRate: Double = SyncProtocol.sampleRate) {
        format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 1
        player.volume = 1
    }

    #if os(macOS)
    /// Select a physical output device before preparing a playback session.
    public func setOutputDevice(_ deviceID: AudioDeviceID) throws {
        guard !started else { return }
        guard let audioUnit = engine.outputNode.audioUnit else {
            throw NSError(
                domain: "Chorus.AudioOutput",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "无法访问本机音频输出单元"]
            )
        }
        var id = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &id,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            throw NSError(
                domain: "Chorus.AudioOutput",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "无法选择本机音频输出设备"]
            )
        }
    }
    #endif

    public func prepareSession(sampleRate: Double) async throws {
        // Tear down the engine only — do NOT schedule an async session deactivate
        // here, or it can race past the activate below and mute playback.
        stopEngine(deactivateSession: false)
        #if os(iOS)
        sessionEpoch &+= 1
        let epoch = sessionEpoch
        try await Self.configureAudioSession(active: true)
        guard epoch == sessionEpoch else {
            throw CancellationError()
        }
        #endif
        format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!
        engine.disconnectNodeOutput(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 1
        player.volume = 1
        try engine.start()
        guard !Task.isCancelled else {
            engine.stop()
            throw CancellationError()
        }
        #if os(iOS)
        guard epoch == sessionEpoch else {
            engine.stop()
            throw CancellationError()
        }
        #endif
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
        enqueue(buffer, playAtLocalUptime: playAtLocalUptime)
    }

    private func enqueue(_ buffer: AVAudioPCMBuffer, playAtLocalUptime: TimeInterval) {
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
        guard started else { return }
        let count = pcmData.count / MemoryLayout<Float>.size
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(count)
        ) else {
            return
        }
        buffer.frameLength = AVAudioFrameCount(count)
        pcmData.withUnsafeBytes { raw in
            guard let dst = buffer.floatChannelData?[0],
                  let source = raw.bindMemory(to: Float.self).baseAddress
            else {
                return
            }
            dst.update(from: source, count: count)
        }
        enqueue(buffer, playAtLocalUptime: playAtLocalUptime)
    }

    public func stop() {
        stopEngine(deactivateSession: true)
    }

    private func stopEngine(deactivateSession: Bool) {
        player.stop()
        if started {
            engine.stop()
            engine.reset()
            started = false
        }
        hasScheduledAudio = false
        isPlaying = false
        #if os(iOS)
        guard deactivateSession else { return }
        sessionEpoch &+= 1
        let epoch = sessionEpoch
        // Deactivate off the main actor so UI stays responsive; ignore if a
        // newer prepareSession has already claimed the session.
        Task(priority: .utility) {
            let stillCurrent = await MainActor.run { epoch == self.sessionEpoch }
            guard stillCurrent else { return }
            try? await Self.configureAudioSession(active: false)
        }
        #endif
    }

    #if os(iOS)
    /// Must not run `setActive` / `setCategory` on the main thread — iOS logs
    /// SessionCore / AVAudioSession warnings and can hitch the UI.
    nonisolated private static func configureAudioSession(active: Bool) async throws {
        try await Task.detached(priority: .userInitiated) {
            let session = AVAudioSession.sharedInstance()
            if active {
                // `.playback` ignores the Ring/Silent hardware switch; media volume
                // (side buttons / Control Center) still applies.
                try session.setCategory(.playback, mode: .default, options: [])
                try session.setActive(true)
            } else {
                try session.setActive(false, options: .notifyOthersOnDeactivation)
            }
        }.value
    }
    #endif

    private func machHostTime(afterSeconds seconds: TimeInterval) -> UInt64 {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        let now = mach_absolute_time()
        let nanos = seconds * 1_000_000_000
        let ticks = nanos * Double(info.denom) / Double(info.numer)
        return now + UInt64(ticks)
    }
}
