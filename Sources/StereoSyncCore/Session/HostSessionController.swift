import Foundation
import Network

@MainActor
public final class HostSessionController: ObservableObject {
    public enum Phase: String {
        case idle
        case advertisingWait = "等待连接"
        case connected
        case syncingClock = "校准时钟"
        case ready
        case playing
        case error
    }

    @Published public private(set) var phase: Phase = .idle
    @Published public private(set) var connectedSpeakers: [DeviceInfo] = []
    @Published public private(set) var statusText = "未开始"
    @Published public private(set) var lastError: String?
    @Published public private(set) var bestRTT: TimeInterval?

    public let localDevice: DeviceInfo
    private var connections: [SyncConnection] = []
    private var synchronizers: [ObjectIdentifier: ClockSynchronizer] = [:]
    private var clockTimers: [ObjectIdentifier: Timer] = [:]
    private let chunker = AudioChunker(samplesPerChunk: 2048)
    private var currentSessionID: UUID?
    private var localPlayer: SyncAudioPlayer?

    public init(deviceName: String? = nil) {
        let resolvedName = deviceName ?? Self.defaultHostName()
        localDevice = DeviceInfo(
            id: UUID().uuidString,
            name: resolvedName,
            role: .host
        )
    }

    public func connect(to peer: DiscoveredPeer) {
        if connections.contains(where: { $0.remoteLabel == peer.endpointDebug }) {
            return
        }
        statusText = "正在连接 \(peer.name)…"
        phase = .connected
        let nw = NWConnection(to: peer.nwEndpoint, using: .tcp)
        attach(SyncConnection(connection: nw, remoteLabel: peer.endpointDebug), displayName: peer.name)
    }

    public func attachIncoming(_ connection: NWConnection) {
        attach(SyncConnection(connection: connection, remoteLabel: "speaker-incoming"), displayName: "Speaker")
    }

    private func attach(_ sync: SyncConnection, displayName: String) {
        connections.append(sync)
        synchronizers[ObjectIdentifier(sync)] = ClockSynchronizer()
        phase = .connected
        statusText = "已连接 \(displayName)，握手中…"

        sync.start { [weak self] event in
            Task { @MainActor in
                self?.handle(event, from: sync)
            }
        }
    }

    public func play(track: DecodedTrack, alsoPlayLocally: Bool) {
        guard !connections.isEmpty else {
            lastError = "没有已连接的扬声器"
            phase = .error
            return
        }

        let sessionID = UUID()
        currentSessionID = sessionID
        let prepare = PrepareSession(sessionID: sessionID, sampleRate: track.sampleRate, channels: 1, title: track.title)
        broadcast(.prepareSession(prepare))

        let lead = SyncProtocol.defaultLeadTime
        let hostPlayAt = HostTime.now() + lead
        let start = StartPlayback(sessionID: sessionID, hostPlayAt: hostPlayAt, leadTime: lead)
        broadcast(.startPlayback(start))

        let chunks = chunker.chunks(from: track, sessionID: sessionID, hostPlayAtZero: hostPlayAt)
        for (header, pcm) in chunks {
            for connection in connections {
                connection.sendAudio(header: header, pcm: pcm)
            }
        }

        if alsoPlayLocally {
            let player = SyncAudioPlayer(sampleRate: track.sampleRate)
            localPlayer = player
            do {
                try player.prepareSession(sampleRate: track.sampleRate)
                player.schedule(pcm: track.pcmFloat32Mono, playAtLocalUptime: hostPlayAt)
            } catch {
                lastError = error.localizedDescription
            }
        }

        phase = .playing
        statusText = "播放中：\(track.title)"
    }

    public func stop() {
        if let sessionID = currentSessionID {
            broadcast(.stopPlayback(sessionID: sessionID))
        }
        localPlayer?.stop()
        localPlayer = nil
        phase = connectedSpeakers.isEmpty ? .idle : .ready
        statusText = "已停止"
    }

    public func teardown() {
        stop()
        for timer in clockTimers.values { timer.invalidate() }
        clockTimers.removeAll()
        connections.forEach { $0.cancel() }
        connections.removeAll()
        connectedSpeakers.removeAll()
        synchronizers.removeAll()
        phase = .idle
        statusText = "未开始"
    }

    private func handle(_ event: SyncConnectionEvent, from connection: SyncConnection) {
        switch event {
        case .connected:
            connection.sendControl(.hello(localDevice))
            startClockPings(for: connection)
        case .disconnected(let reason):
            remove(connection, reason: reason)
        case .control(let payload):
            handleControl(payload, from: connection)
        case .audio:
            break
        }
    }

    private func handleControl(_ payload: ControlPayload, from connection: SyncConnection) {
        switch payload {
        case .hello(let info), .welcome(let info):
            if !connectedSpeakers.contains(where: { $0.id == info.id }) {
                connectedSpeakers.append(info)
            }
            connection.sendControl(.welcome(localDevice))
            phase = .syncingClock
            statusText = "已连接 \(info.name)，校准时钟…"
        case .clockPong(let pong):
            let syncer = synchronizers[ObjectIdentifier(connection)]
            syncer?.recordPong(pong, hostReceiveTime: HostTime.now())
            bestRTT = syncer?.bestEstimate?.roundTrip
            if let rtt = bestRTT, rtt < 0.08 {
                phase = .ready
                statusText = "就绪（RTT ≈ \(Int(rtt * 1000)) ms）"
            }
        case .goodbye(let id):
            connectedSpeakers.removeAll { $0.id == id }
        default:
            break
        }
    }

    private func startClockPings(for connection: SyncConnection) {
        let key = ObjectIdentifier(connection)
        clockTimers[key]?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self, weak connection] _ in
            guard let self, let connection else { return }
            Task { @MainActor in
                let ping = ClockPing(hostSendTime: HostTime.now())
                connection.sendControl(.clockPing(ping))
            }
        }
        clockTimers[key] = timer
    }

    private func remove(_ connection: SyncConnection, reason: String?) {
        let key = ObjectIdentifier(connection)
        clockTimers[key]?.invalidate()
        clockTimers[key] = nil
        synchronizers[key] = nil
        connections.removeAll { $0 === connection }
        if connections.isEmpty {
            connectedSpeakers.removeAll()
            phase = .idle
            statusText = reason.map { "连接断开：\($0)" } ?? "连接断开"
        }
    }

    private func broadcast(_ payload: ControlPayload) {
        connections.forEach { $0.sendControl(payload) }
    }

    public static func defaultHostName() -> String {
        #if os(macOS)
        return Host.current().localizedName ?? "Mac Host"
        #else
        return "Host"
        #endif
    }
}
