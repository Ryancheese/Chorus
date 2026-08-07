import XCTest
@testable import ChorusCore

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

    func testStopAcknowledgementRoundTrip() throws {
        let id = UUID()
        let data = try MessageCodec.encodeControl(.stopAcknowledged(sessionID: id))
        let decoded = try MessageCodec.decodeControl(data)
        guard case .stopAcknowledged(let receivedID) = decoded else {
            return XCTFail("expected stop acknowledgement")
        }
        XCTAssertEqual(receivedID, id)
    }

    func testClockOffsetRoundTrip() throws {
        let data = try MessageCodec.encodeControl(.clockOffset(seconds: -12.345))
        let decoded = try MessageCodec.decodeControl(data)
        guard case .clockOffset(let seconds) = decoded else {
            return XCTFail("expected clock offset")
        }
        XCTAssertEqual(seconds, -12.345, accuracy: 0.000_001)
    }

    @MainActor
    func testJitterBufferWaitsForTargetThenDrainsInOrder() {
        let id = UUID()
        let buffer = AudioJitterBuffer(sampleRate: 100, targetDuration: 0.2)
        let first = AudioChunkHeader(sessionID: id, sequence: 0, sampleIndex: 0, sampleCount: 10, hostPlayAt: 0)
        let second = AudioChunkHeader(sessionID: id, sequence: 1, sampleIndex: 10, sampleCount: 10, hostPlayAt: 0.1)

        XCTAssertTrue(buffer.append(header: first, pcm: Data()).isEmpty)
        let ready = buffer.append(header: second, pcm: Data())
        XCTAssertEqual(ready.map(\.header.sequence), [0, 1])
    }

    func testStableLeadTimeNeverDropsBelowBufferRequirement() {
        var leadTime = AdaptiveLeadTime()
        leadTime.record(roundTrip: 0.01)
        XCTAssertGreaterThanOrEqual(leadTime.recommendedLeadTime, 1.2)
    }

    func testPrimaryLocalesContainTranslatedHelpAction() {
        XCTAssertEqual(L10n.supportedLanguageCodes, ["en", "zh-Hans", "ja", "ko"])
        for languageCode in L10n.supportedLanguageCodes {
            XCTAssertNotEqual(L10n.text("action.help", languageCode: languageCode), "action.help")
            XCTAssertNotEqual(L10n.text("error.connect.timeout", languageCode: languageCode), "error.connect.timeout")
            XCTAssertNotEqual(L10n.text("network.hint.multicast", languageCode: languageCode), "network.hint.multicast")
        }
    }

    func testSameIPv4SubnetDetection() {
        XCTAssertTrue(LocalNetworkAddress.sameIPv4Subnet("192.168.1.8", "192.168.1.20"))
        XCTAssertFalse(LocalNetworkAddress.sameIPv4Subnet("192.168.1.8", "10.0.0.5"))
        XCTAssertFalse(LocalNetworkAddress.sameIPv4Subnet("not-an-ip", "192.168.1.1"))
    }

    func testPersonalHotspotDetection() {
        XCTAssertTrue(LocalNetworkAddress.looksLikePersonalHotspot("172.20.10.5"))
        XCTAssertTrue(LocalNetworkAddress.looksLikePersonalHotspot("172.20.10.1"))
        XCTAssertTrue(LocalNetworkAddress.looksLikePersonalHotspot("192.168.43.2"))
        XCTAssertFalse(LocalNetworkAddress.looksLikePersonalHotspot("192.168.1.8"))
    }

    func testVpnInterfacesPresentRequiresPrimaryTunnel() {
        // Must follow primaryAddress(), not "any utun has an IPv4".
        let primaryIsTunnel = LocalNetworkAddress.primaryAddress()
            .map { LocalNetworkAddress.isVPNInterfaceName($0.interface) } ?? false
        XCTAssertEqual(LocalNetworkAddress.vpnInterfacesPresent(), primaryIsTunnel)
    }

    @MainActor
    func testLanguageSelectionPersistsAndDefaultsToChineseFallback() {
        let settings = LanguageSettings()
        let original = settings.selection
        defer { settings.selection = original }

        settings.selection = .japanese
        XCTAssertEqual(L10n.text("action.help"), "ヘルプ")
        settings.selection = .chinese
        XCTAssertEqual(L10n.text("action.help"), "使用帮助")
    }

    @MainActor
    func testAppearanceSelectionMapsColorSchemeAndPersists() {
        let settings = AppearanceSettings()
        let original = settings.selection
        defer { settings.selection = original }

        settings.selection = .light
        XCTAssertEqual(settings.selection.preferredColorScheme, .light)
        settings.selection = .dark
        XCTAssertEqual(settings.selection.preferredColorScheme, .dark)
        settings.selection = .system
        XCTAssertNil(settings.selection.preferredColorScheme)

        let restored = AppearanceSettings()
        XCTAssertEqual(restored.selection, .system)
        settings.selection = .dark
        XCTAssertEqual(AppearanceSettings().selection, .dark)
    }

    func testSpeakerLiveActivityStatusMapping() {
        XCTAssertEqual(SpeakerActivityStatus.from(phase: .advertising), .waiting)
        XCTAssertEqual(SpeakerActivityStatus.from(phase: .ready), .connected)
        XCTAssertEqual(SpeakerActivityStatus.from(phase: .playing), .playing)
        XCTAssertNil(SpeakerActivityStatus.from(phase: .idle))
    }

    #if os(macOS)
    func testBlackHoleDeviceIsRecognized() {
        let device = AudioDevice(id: 1, name: "BlackHole 2ch", inputChannels: 2, outputChannels: 2)
        XCTAssertTrue(device.isBlackHole)
    }
    #endif
}
