#if os(macOS)
import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

/// Reads system audio after macOS has routed it to BlackHole 2ch.
@MainActor
public final class BlackHoleAudioCapture {
    public enum CaptureError: LocalizedError {
        case cannotSelectInputDevice
        case invalidInputFormat
        case cannotStartEngine(Error)

        public var errorDescription: String? {
            switch self {
            case .cannotSelectInputDevice:
                return "无法选择 BlackHole 2ch 作为输入设备"
            case .invalidInputFormat:
                return "BlackHole 未提供有效的音频格式，请确认已重启 Mac 并将系统输出设为 BlackHole 2ch"
            case .cannotStartEngine(let error):
                return "无法启动 BlackHole 音频采集：\(error.localizedDescription)"
            }
        }
    }

    public var onSamples: (([Float], Double) -> Void)?
    private let engine = AVAudioEngine()
    private var started = false

    public init() {}

    public func start(deviceID: AudioDeviceID) throws {
        stop()

        guard let audioUnit = engine.inputNode.audioUnit else {
            throw CaptureError.cannotSelectInputDevice
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
        // Some macOS versions reject setting CurrentDevice on AVAudioEngine's
        // input node even when the system input has already switched. The host
        // switches the default input before calling this method, so in that
        // case the input node will still bind to the requested BlackHole device.
        guard status == noErr || AudioDeviceList.defaultInputID() == deviceID else {
            throw CaptureError.cannotSelectInputDevice
        }

        let input = engine.inputNode
        // An input node produces captured PCM on its output bus. Reading its input
        // bus can yield a zero-channel format and causes AVAudioEngine to abort.
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw CaptureError.invalidInputFormat
        }
        input.installTap(onBus: 0, bufferSize: 2_048, format: nil) { [weak self] buffer, _ in
            guard let self else { return }
            let samples = Self.monoSamples(from: buffer)
            guard !samples.isEmpty else { return }
            Task { @MainActor in
                self.onSamples?(samples, buffer.format.sampleRate)
            }
        }

        do {
            try engine.start()
            started = true
        } catch {
            input.removeTap(onBus: 0)
            throw CaptureError.cannotStartEngine(error)
        }
    }

    public func stop() {
        engine.inputNode.removeTap(onBus: 0)
        if started {
            engine.stop()
            started = false
        }
    }

    private nonisolated static func monoSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameCount > 0, channelCount > 0 else {
            return []
        }

        if let channels = buffer.floatChannelData {
            return downmix(channels, frameCount: frameCount, channelCount: channelCount) { $0 }
        }
        if let channels = buffer.int16ChannelData {
            return downmix(channels, frameCount: frameCount, channelCount: channelCount) {
                Float($0) / Float(Int16.max)
            }
        }
        if let channels = buffer.int32ChannelData {
            return downmix(channels, frameCount: frameCount, channelCount: channelCount) {
                Float($0) / Float(Int32.max)
            }
        }
        return []
    }

    private nonisolated static func downmix<T>(
        _ channels: UnsafePointer<UnsafeMutablePointer<T>>,
        frameCount: Int,
        channelCount: Int,
        convert: (T) -> Float
    ) -> [Float] {
        if channelCount == 1 {
            return Array(UnsafeBufferPointer(start: channels[0], count: frameCount)).map(convert)
        }
        var mono = [Float](repeating: 0, count: frameCount)
        for channel in 0..<channelCount {
            let source = channels[channel]
            for frame in 0..<frameCount {
                mono[frame] += convert(source[frame]) / Float(channelCount)
            }
        }
        return mono
    }
}
#endif
