import Foundation
import Network

#if canImport(UIKit)
import UIKit
#endif

@MainActor
public final class SpeakerSessionController: ObservableObject {
    public enum Phase: Equatable {
        case idle
        case advertising
        case connecting
        case connected
        case syncing
        case ready
        case playing
        case error

        public var displayName: String {
            switch self {
            case .idle: L10n.text("phase.idle")
            case .advertising: L10n.text("phase.discoverable")
            case .connecting: L10n.text("phase.connecting")
            case .connected: L10n.text("phase.connected")
            case .syncing: L10n.text("phase.calibrating")
            case .ready: L10n.text("phase.ready")
            case .playing: L10n.text("phase.playing")
            case .error: L10n.text("phase.error")
            }
        }
    }

    @Published public private(set) var phase: Phase = .idle
    @Published public private(set) var hostName: String?
    @Published public private(set) var statusText = "点击开始广播"
    @Published public private(set) var lastError: String?
    @Published public private(set) var sessionTitle: String?
    @Published public private(set) var clockOffsetMs: Double?
    @Published public private(set) var isAdvertising = false
    @Published public private(set) var connectionAddress: String?

    public let localDevice: DeviceInfo
    private let advertiser: PeerAdvertiser
    private var connection: SyncConnection?
    private var audioConnection: SyncConnection?
    /// Approximate `localTime - hostTime` from the latest ping.
    private var offset: TimeInterval = 0
    /// Frozen for a playing session so adjacent chunks share one timing basis.
    private var playbackOffset: TimeInterval?
    private let player = SyncAudioPlayer()
    private var sessionID: UUID?
    private var jitterBuffer: AudioJitterBuffer?
    private var lastStoppedSessionID: UUID?

    public init(deviceName: String? = nil) {
        let resolvedName = deviceName ?? Self.defaultSpeakerName()
        localDevice = DeviceInfo(id: UUID().uuidString, name: resolvedName, role: .speaker)
        advertiser = PeerAdvertiser(deviceName: resolvedName)
        advertiser.onConnection = { [weak self] nw in
            Task { @MainActor in
                self?.accept(nw)
            }
        }
        advertiser.onStatusChange = { [weak self] in
            self?.syncFromAdvertiser()
        }
    }

    public func startAdvertising() {
        lastError = nil
        advertiser.start()
        isAdvertising = true
        phase = .advertising
        refreshConnectionAddress()
        statusText = "等待 Mac 连接…"
        syncFromAdvertiser()
    }

    private func syncFromAdvertiser() {
        refreshConnectionAddress()
        isAdvertising = advertiser.isAdvertising
        lastError = advertiser.lastError
        if advertiser.isAdvertising, phase == .idle || phase == .error {
            phase = .advertising
            statusText = advertiser.bonjourUnavailable
                ? "等待 Mac 手动连接…"
                : "等待 Mac 连接…"
        }
        if !advertiser.isAdvertising, let err = advertiser.lastError, phase == .advertising {
            phase = .error
            statusText = err
        }
    }

    public func stopAll() {
        player.stop()
        connection?.cancel()
        audioConnection?.cancel()
        connection = nil
        audioConnection = nil
        jitterBuffer = nil
        sessionID = nil
        lastStoppedSessionID = nil
        playbackOffset = nil
        advertiser.stop()
        isAdvertising = false
        connectionAddress = nil
        phase = .idle
        statusText = "已停止"
        hostName = nil
        sessionTitle = nil
    }

    private func refreshConnectionAddress() {
        let ip = advertiser.localIPv4 ?? LocalNetworkAddress.primaryIPv4() ?? "未知IP"
        let port = advertiser.listeningPort
        connectionAddress = "\(ip):\(port)"
    }

    private func accept(_ nw: NWConnection) {
        let sync = SyncConnection(connection: nw, remoteLabel: "host")
        phase = .connecting
        statusText = "主机连入，握手中…"
        sync.start { [weak self] event in
            Task { @MainActor in
                self?.handle(event, from: sync)
            }
        }
    }

    private func handle(_ event: SyncConnectionEvent, from sync: SyncConnection) {
        switch event {
        case .connected:
            break
        case .disconnected(let reason):
            if sync === connection {
                player.stop()
                jitterBuffer = nil
                sessionID = nil
                playbackOffset = nil
                connection = nil
                phase = .advertising
                statusText = reason.map { "断开：\($0)" } ?? "主机断开，继续等待…"
                hostName = nil
            } else if sync === audioConnection {
                audioConnection = nil
                if phase == .playing {
                    player.stop()
                    playbackOffset = nil
                    phase = .ready
                    statusText = "音频通道断开"
                }
            }
        case .control(let payload):
            handleControl(payload, from: sync)
        case .audio(let header, let pcm):
            guard sync === audioConnection else { return }
            handleAudio(header: header, pcm: pcm)
        }
    }

    private func handleControl(_ payload: ControlPayload, from sync: SyncConnection) {
        switch payload {
        case .audioChannelHello:
            audioConnection?.cancel()
            audioConnection = sync
        case .hello(let info):
            connection?.cancel()
            connection = sync
            hostName = info.name
            connection?.sendControl(.welcome(localDevice))
            phase = .syncing
            statusText = "已连接 \(info.name)"
        case .welcome(let info):
            hostName = info.name
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
            if phase != .playing {
                phase = .ready
            }
        case .clockOffset(let seconds):
            offset = seconds
            clockOffsetMs = seconds * 1000
        case .prepareSession(let session):
            guard sync === connection else { return }
            sessionID = session.sessionID
            lastStoppedSessionID = nil
            sessionTitle = session.title
            do {
                try player.prepareSession(sampleRate: session.sampleRate)
                jitterBuffer = AudioJitterBuffer(sampleRate: session.sampleRate)
                statusText = "准备播放：\(session.title)"
            } catch {
                lastError = error.localizedDescription
                phase = .error
            }
        case .startPlayback(let start):
            guard sync === connection, start.sessionID == sessionID else { return }
            sessionID = start.sessionID
            playbackOffset = offset
            statusText = "即将同步起播…"
            phase = .playing
        case .stopPlayback(let id):
            guard sync === connection else { return }
            if id == lastStoppedSessionID {
                connection?.sendControl(.stopAcknowledged(sessionID: id))
                return
            }
            guard id == sessionID else { return }
            sessionID = nil
            lastStoppedSessionID = id
            jitterBuffer = nil
            playbackOffset = nil
            player.stop()
            phase = .ready
            statusText = "主机已停止"
            sessionTitle = nil
            connection?.sendControl(.stopAcknowledged(sessionID: id))
        case .goodbye:
            // Keep the existing listener alive. Cancelling it and immediately
            // rebinding the fixed port races with Network.framework's teardown
            // and produces the misleading "Address already in use" error.
            player.stop()
            connection?.cancel()
            audioConnection?.cancel()
            connection = nil
            audioConnection = nil
            jitterBuffer = nil
            sessionID = nil
            lastStoppedSessionID = nil
            playbackOffset = nil
            hostName = nil
            sessionTitle = nil
            lastError = nil
            phase = .advertising
            statusText = "Mac 已移除本机，仍可等待新的连接"
        default:
            break
        }
    }

    private func handleAudio(header: AudioChunkHeader, pcm: Data) {
        guard header.sessionID == sessionID, let jitterBuffer else { return }
        for chunk in jitterBuffer.append(header: header, pcm: pcm) {
            let localPlayAt = chunk.header.hostPlayAt + (playbackOffset ?? offset)
            // Playing a late chunk immediately causes an audible catch-up stutter.
            guard localPlayAt > HostTime.now() + 0.02 else { continue }
            player.scheduleChunk(pcmData: chunk.pcm, playAtLocalUptime: localPlayAt)
        }
        if player.isPlaying {
            phase = .playing
            statusText = sessionTitle.map { "播放中：\($0)" } ?? "播放中"
        }
    }

    public static func defaultSpeakerName() -> String {
        #if os(iOS)
        return UIDevice.current.name
        #else
        return "Speaker"
        #endif
    }
}
