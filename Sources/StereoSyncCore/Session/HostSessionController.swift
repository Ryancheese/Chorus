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
    @Published public private(set) var isPaused = false

    public let localDevice: DeviceInfo
    private var connections: [SyncConnection] = []
    private var audioConnections: [SyncConnection] = []
    private var synchronizers: [ObjectIdentifier: ClockSynchronizer] = [:]
    private var clockTimers: [ObjectIdentifier: Timer] = [:]
    private var adaptiveLeadTime = AdaptiveLeadTime()
    private let chunker = AudioChunker(samplesPerChunk: 2048)
    private var currentSessionID: UUID?
    private var localPlayer: SyncAudioPlayer?
    private var audioStreamTask: Task<Void, Never>?
    private var pendingStopSessionIDs: Set<UUID> = []
    private var pausedStopSessionIDs: Set<UUID> = []
    private var pausedTrack: DecodedTrack?
    private var currentTrack: DecodedTrack?
    private var currentTrackStartAt: TimeInterval?
    private var playsLocally = false

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
        let control = NWConnection(to: peer.nwEndpoint, using: .tcp)
        let audio = NWConnection(to: peer.nwEndpoint, using: .tcp)
        attach(
            SyncConnection(connection: control, remoteLabel: peer.endpointDebug),
            audio: SyncConnection(connection: audio, remoteLabel: "\(peer.endpointDebug)-audio"),
            displayName: peer.name
        )
    }

    /// Manual LAN connect when Bonjour discovery is blocked.
    public func connect(host: String, port: UInt16 = SyncBonjour.controlPort) {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastError = "请输入手机显示的 IP"
            return
        }
        let label = "\(trimmed):\(port)"
        if connections.contains(where: { $0.remoteLabel == label }) {
            return
        }
        statusText = "正在连接 \(label)…"
        phase = .connected
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(trimmed),
            port: NWEndpoint.Port(rawValue: port)!
        )
        let control = NWConnection(to: endpoint, using: .tcp)
        let audio = NWConnection(to: endpoint, using: .tcp)
        attach(
            SyncConnection(connection: control, remoteLabel: label),
            audio: SyncConnection(connection: audio, remoteLabel: "\(label)-audio"),
            displayName: label
        )
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

    private func attach(_ control: SyncConnection, audio: SyncConnection, displayName: String) {
        attach(control, displayName: displayName)
        audioConnections.append(audio)
        audio.start { [weak self] event in
            Task { @MainActor in
                self?.handleAudioChannel(event, from: audio)
            }
        }
    }

    public func play(track: DecodedTrack, alsoPlayLocally: Bool) {
        guard !connections.isEmpty, !audioConnections.isEmpty else {
            lastError = "没有已连接的扬声器"
            phase = .error
            return
        }

        audioStreamTask?.cancel()
        isPaused = false
        pausedTrack = nil
        currentTrack = track
        playsLocally = alsoPlayLocally
        let sessionID = UUID()
        currentSessionID = sessionID
        let prepare = PrepareSession(sessionID: sessionID, sampleRate: track.sampleRate, channels: 1, title: track.title)
        broadcast(.prepareSession(prepare))

        let lead = adaptiveLeadTime.recommendedLeadTime
        let hostPlayAt = HostTime.now() + lead
        currentTrackStartAt = hostPlayAt
        let start = StartPlayback(sessionID: sessionID, hostPlayAt: hostPlayAt, leadTime: lead)
        broadcast(.startPlayback(start))

        let chunks = chunker.chunks(from: track, sessionID: sessionID, hostPlayAtZero: hostPlayAt)
        let recipients = audioConnections
        // Keep enough audio ahead of the speaker to absorb typical Wi‑Fi bursts.
        let targetBufferedAudio = min(max(0.9, lead * 0.8), 1.1)
        audioStreamTask = Task { [weak self] in
            for (header, pcm) in chunks {
                guard !Task.isCancelled, self?.currentSessionID == sessionID else { return }
                let wait = header.hostPlayAt - HostTime.now() - targetBufferedAudio
                if wait > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                }
                for connection in recipients {
                    guard !Task.isCancelled, self?.currentSessionID == sessionID else { return }
                    await connection.sendAudio(header: header, pcm: pcm)
                }
            }
            if self?.currentSessionID == sessionID {
                self?.audioStreamTask = nil
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
        // Send on the independent control channel before cancelling audio work.
        // This gets the session invalidation to the speaker as early as possible.
        if let sessionID = currentSessionID {
            pausedStopSessionIDs.remove(sessionID)
            requestStop(sessionID: sessionID)
        }
        audioStreamTask?.cancel()
        audioStreamTask = nil
        currentSessionID = nil
        currentTrack = nil
        currentTrackStartAt = nil
        pausedTrack = nil
        isPaused = false
        localPlayer?.stop()
        localPlayer = nil
        phase = connectedSpeakers.isEmpty ? .idle : .ready
        statusText = "已停止"
    }

    public func pause() {
        guard let track = currentTrack, let startAt = currentTrackStartAt else { return }
        let elapsed = max(0, HostTime.now() - startAt)
        let sampleIndex = min(track.pcmFloat32Mono.count, Int(elapsed * track.sampleRate))
        let remainingSamples = Array(track.pcmFloat32Mono.dropFirst(sampleIndex))

        if let sessionID = currentSessionID {
            pausedStopSessionIDs.insert(sessionID)
            requestStop(sessionID: sessionID)
        }
        audioStreamTask?.cancel()
        audioStreamTask = nil
        currentSessionID = nil
        currentTrackStartAt = nil
        currentTrack = nil
        localPlayer?.stop()
        localPlayer = nil

        pausedTrack = DecodedTrack(
            title: track.title,
            sampleRate: track.sampleRate,
            channelCount: track.channelCount,
            pcmFloat32Mono: remainingSamples
        )
        isPaused = !remainingSamples.isEmpty
        phase = connectedSpeakers.isEmpty ? .idle : .ready
        statusText = isPaused ? "已暂停" : "已播放完毕"
    }

    public func resume() {
        guard let pausedTrack else { return }
        play(track: pausedTrack, alsoPlayLocally: playsLocally)
    }

    private func requestStop(sessionID: UUID) {
        pendingStopSessionIDs.insert(sessionID)
        broadcast(.stopPlayback(sessionID: sessionID))

        Task { [weak self] in
            for _ in 0..<3 {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard let self, self.pendingStopSessionIDs.contains(sessionID) else { return }
                self.broadcast(.stopPlayback(sessionID: sessionID))
            }
            guard let self, self.pendingStopSessionIDs.remove(sessionID) != nil else { return }
            self.pausedStopSessionIDs.remove(sessionID)
            self.lastError = "扬声器未确认停止，请检查连接状态"
        }
    }

    public func teardown() {
        stop()
        for timer in clockTimers.values { timer.invalidate() }
        clockTimers.removeAll()
        connections.forEach { $0.cancel() }
        audioConnections.forEach { $0.cancel() }
        connections.removeAll()
        audioConnections.removeAll()
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

    private func handleAudioChannel(_ event: SyncConnectionEvent, from connection: SyncConnection) {
        switch event {
        case .connected:
            connection.sendControl(.audioChannelHello(deviceID: localDevice.id))
        case .disconnected:
            audioConnections.removeAll { $0 === connection }
            if phase == .playing {
                lastError = "音频通道断开"
                stop()
            }
        case .control, .audio:
            break
        }
    }

    private func handleControl(_ payload: ControlPayload, from connection: SyncConnection) {
        switch payload {
        case .hello(let info):
            if !connectedSpeakers.contains(where: { $0.id == info.id }) {
                connectedSpeakers.append(info)
            }
            connection.sendControl(.welcome(localDevice))
            phase = .syncingClock
            statusText = "已连接 \(info.name)，校准时钟…"
        case .welcome(let info):
            if !connectedSpeakers.contains(where: { $0.id == info.id }) {
                connectedSpeakers.append(info)
            }
            phase = .syncingClock
            statusText = "已连接 \(info.name)，校准时钟…"
        case .clockPong(let pong):
            let syncer = synchronizers[ObjectIdentifier(connection)]
            syncer?.recordPong(pong, hostReceiveTime: HostTime.now())
            bestRTT = syncer?.bestEstimate?.roundTrip
            if let bestRTT {
                adaptiveLeadTime.record(roundTrip: bestRTT)
            }
            if let rtt = bestRTT, rtt < 0.08, phase != .playing, !isPaused {
                phase = .ready
                statusText = "就绪（RTT ≈ \(Int(rtt * 1000)) ms）"
            }
        case .goodbye(let id):
            connectedSpeakers.removeAll { $0.id == id }
        case .stopAcknowledged(let id):
            guard pendingStopSessionIDs.remove(id) != nil else { return }
            let wasPaused = pausedStopSessionIDs.remove(id) != nil
            if currentSessionID == nil {
                statusText = wasPaused ? "已暂停（已确认）" : "已停止（已确认）"
            }
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
        return Foundation.Host.current().localizedName ?? "Mac Host"
        #else
        return "Host"
        #endif
    }
}
