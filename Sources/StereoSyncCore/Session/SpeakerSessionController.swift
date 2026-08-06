import Foundation
import Network

#if canImport(UIKit)
import UIKit
#endif

@MainActor
public final class SpeakerSessionController: ObservableObject {
    public enum Phase: String {
        case idle
        case advertising = "可被发现"
        case connecting
        case connected
        case syncing = "校准时钟"
        case ready
        case playing
        case error
    }

    @Published public private(set) var phase: Phase = .idle
    @Published public private(set) var hostName: String?
    @Published public private(set) var statusText = "点击开始广播"
    @Published public private(set) var lastError: String?
    @Published public private(set) var sessionTitle: String?
    @Published public private(set) var clockOffsetMs: Double?
    @Published public private(set) var isAdvertising = false

    public let localDevice: DeviceInfo
    private let advertiser: PeerAdvertiser
    private var connection: SyncConnection?
    /// Approximate `localTime - hostTime` from the latest ping.
    private var offset: TimeInterval = 0
    private let player = SyncAudioPlayer()
    private var sessionID: UUID?

    public init(deviceName: String? = nil) {
        let resolvedName = deviceName ?? Self.defaultSpeakerName()
        localDevice = DeviceInfo(id: UUID().uuidString, name: resolvedName, role: .speaker)
        advertiser = PeerAdvertiser(deviceName: resolvedName)
        advertiser.onConnection = { [weak self] nw in
            Task { @MainActor in
                self?.accept(nw)
            }
        }
    }

    public func startAdvertising() {
        advertiser.start()
        isAdvertising = true
        phase = .advertising
        statusText = "等待 Mac 连接…"
        if let err = advertiser.lastError {
            lastError = err
            phase = .error
            statusText = err
        }
    }

    public func stopAll() {
        player.stop()
        connection?.cancel()
        connection = nil
        advertiser.stop()
        isAdvertising = false
        phase = .idle
        statusText = "已停止"
        hostName = nil
        sessionTitle = nil
    }

    private func accept(_ nw: NWConnection) {
        connection?.cancel()
        let sync = SyncConnection(connection: nw, remoteLabel: "host")
        connection = sync
        phase = .connecting
        statusText = "主机连入，握手中…"
        sync.start { [weak self] event in
            Task { @MainActor in
                self?.handle(event)
            }
        }
    }

    private func handle(_ event: SyncConnectionEvent) {
        switch event {
        case .connected:
            connection?.sendControl(.hello(localDevice))
            phase = .connected
        case .disconnected(let reason):
            player.stop()
            phase = .advertising
            statusText = reason.map { "断开：\($0)" } ?? "主机断开，继续等待…"
            hostName = nil
        case .control(let payload):
            handleControl(payload)
        case .audio(let header, let pcm):
            handleAudio(header: header, pcm: pcm)
        }
    }

    private func handleControl(_ payload: ControlPayload) {
        switch payload {
        case .hello(let info), .welcome(let info):
            hostName = info.name
            connection?.sendControl(.welcome(localDevice))
            phase = .syncing
            statusText = "已连接 \(info.name)"
        case .clockPing(let ping):
            let receive = HostTime.now()
            let pong = ClockPong(
                pingID: ping.pingID,
                hostSendTime: ping.hostSendTime,
                speakerReceiveTime: receive,
                speakerSendTime: HostTime.now()
            )
            connection?.sendControl(.clockPong(pong))
            offset = receive - ping.hostSendTime
            clockOffsetMs = offset * 1000
            if phase != .playing {
                phase = .ready
            }
        case .prepareSession(let session):
            sessionID = session.sessionID
            sessionTitle = session.title
            do {
                try player.prepareSession(sampleRate: session.sampleRate)
                statusText = "准备播放：\(session.title)"
            } catch {
                lastError = error.localizedDescription
                phase = .error
            }
        case .startPlayback(let start):
            sessionID = start.sessionID
            statusText = "即将同步起播…"
            phase = .playing
        case .stopPlayback:
            player.stop()
            phase = .ready
            statusText = "主机已停止"
            sessionTitle = nil
        case .goodbye:
            stopAll()
            startAdvertising()
        default:
            break
        }
    }

    private func handleAudio(header: AudioChunkHeader, pcm: Data) {
        guard sessionID == nil || header.sessionID == sessionID else { return }
        let localPlayAt = header.hostPlayAt + offset
        player.scheduleChunk(pcmData: pcm, playAtLocalUptime: localPlayAt)
        phase = .playing
        statusText = sessionTitle.map { "播放中：\($0)" } ?? "播放中"
    }

    public static func defaultSpeakerName() -> String {
        #if os(iOS)
        return UIDevice.current.name
        #else
        return "Speaker"
        #endif
    }
}
