import XCTest
@testable import StereoSyncCore

final class ProtocolTests: XCTestCase {
    func testControlRoundTrip() throws {
        let info = DeviceInfo(id: "abc", name: "Phone", role: .speaker)
        let data = try MessageCodec.encodeControl(.hello(info))
        let decoded = try MessageCodec.decodeControl(data)
        guard case .hello(let again) = decoded else {
            return XCTFail("expected hello")
        }
        XCTAssertEqual(again.id, "abc")
        XCTAssertEqual(again.name, "Phone")
    }

    func testAudioFrameRoundTrip() throws {
        let header = AudioChunkHeader(
            sessionID: UUID(),
            sequence: 3,
            sampleIndex: 2048,
            sampleCount: 2,
            hostPlayAt: 12.5
        )
        var samples: [Float] = [0.25, -0.5]
        let pcm = samples.withUnsafeBufferPointer { Data(buffer: $0) }
        let frame = try MessageCodec.encodeAudioFrame(header: header, pcm: pcm)
        let (decodedHeader, decodedPCM) = try MessageCodec.decodeAudioFrame(frame)
        XCTAssertEqual(decodedHeader.sequence, 3)
        XCTAssertEqual(decodedPCM, pcm)
    }

    func testFramePacking() {
        let unpacker = FrameIO.Unpacker()
        let a = FrameIO.pack(Data([1, 2, 3]))
        let b = FrameIO.pack(Data([9]))
        let frames = unpacker.append(a + b)
        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(frames[0], Data([1, 2, 3]))
        XCTAssertEqual(frames[1], Data([9]))
    }

    func testClockOffsetHeuristic() {
        let sync = ClockSynchronizer()
        let pingSend: TimeInterval = 100
        let speakerRecv: TimeInterval = 100.02
        let speakerSend: TimeInterval = 100.021
        let hostRecv: TimeInterval = 100.04
        let pong = ClockPong(
            pingID: UUID(),
            hostSendTime: pingSend,
            speakerReceiveTime: speakerRecv,
            speakerSendTime: speakerSend
        )
        sync.recordPong(pong, hostReceiveTime: hostRecv)
        let best = sync.bestEstimate
        XCTAssertNotNil(best)
        XCTAssertEqual(best!.roundTrip, 0.04, accuracy: 0.0001)
    }
}
