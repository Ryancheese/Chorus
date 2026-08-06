import AVFoundation
import Foundation

public struct DecodedTrack: Sendable {
    public var title: String
    public var sampleRate: Double
    public var channelCount: AVAudioChannelCount
    public var pcmFloat32Mono: [Float]

    public var duration: TimeInterval {
        Double(pcmFloat32Mono.count) / sampleRate
    }
}

public enum AudioFileLoader {
    /// Loads any AVFoundation-readable file and converts to mono Float32 @ SyncProtocol.sampleRate.
    public static func load(url: URL) throws -> DecodedTrack {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw LoaderError.bufferAllocationFailed
        }
        try file.read(into: buffer)

        let targetRate = SyncProtocol.sampleRate
        let mono = try convertToMonoFloat32(buffer: buffer, targetSampleRate: targetRate)
        return DecodedTrack(
            title: url.deletingPathExtension().lastPathComponent,
            sampleRate: targetRate,
            channelCount: 1,
            pcmFloat32Mono: mono
        )
    }

    private static func convertToMonoFloat32(buffer: AVAudioPCMBuffer, targetSampleRate: Double) throws -> [Float] {
        let sourceFormat = buffer.format
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        )!
        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw LoaderError.converterUnavailable
        }

        let ratio = targetSampleRate / sourceFormat.sampleRate
        let outFrames = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outFrames) else {
            throw LoaderError.bufferAllocationFailed
        }

        var error: NSError?
        var consumed = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        converter.convert(to: outBuffer, error: &error, withInputFrom: inputBlock)
        if let error { throw error }

        guard let channel = outBuffer.floatChannelData?[0] else {
            throw LoaderError.missingChannelData
        }
        return Array(UnsafeBufferPointer(start: channel, count: Int(outBuffer.frameLength)))
    }

    public enum LoaderError: Error {
        case bufferAllocationFailed
        case converterUnavailable
        case missingChannelData
    }
}

/// Splits mono PCM into network-sized chunks.
public struct AudioChunker {
    public let samplesPerChunk: Int

    public init(samplesPerChunk: Int = 1024) {
        self.samplesPerChunk = samplesPerChunk
    }

    public func chunks(from track: DecodedTrack, sessionID: UUID, hostPlayAtZero: TimeInterval) -> [(AudioChunkHeader, Data)] {
        var result: [(AudioChunkHeader, Data)] = []
        var index = 0
        var sequence: UInt64 = 0
        while index < track.pcmFloat32Mono.count {
            let end = min(index + samplesPerChunk, track.pcmFloat32Mono.count)
            let slice = Array(track.pcmFloat32Mono[index..<end])
            let data = slice.withUnsafeBufferPointer { Data(buffer: $0) }
            let playAt = hostPlayAtZero + Double(index) / track.sampleRate
            let header = AudioChunkHeader(
                sessionID: sessionID,
                sequence: sequence,
                sampleIndex: UInt64(index),
                sampleCount: UInt32(slice.count),
                hostPlayAt: playAt
            )
            result.append((header, data))
            index = end
            sequence += 1
        }
        return result
    }
}
