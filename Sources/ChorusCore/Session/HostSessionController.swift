import Foundation
import Network
#if os(macOS)
import AVFoundation
import CoreAudio
#endif

@MainActor
public final class HostSessionController: ObservableObject {
    public enum Phase {
        case idle
        case advertisingWait
        case connected
        case syncingClock
        case ready
        case playing
        case error

        public var displayName: String {
            switch self {
            case .idle: L10n.text("phase.idle")
            case .advertisingWait: L10n.text("phase.discoverable")
            case .connected: L10n.text("phase.connected")
            case .syncingClock: L10n.text("phase.calibrating")
            case .ready: L10n.text("phase.ready")
            case .playing: L10n.text("phase.playing")
            case .error: L10n.text("phase.error")
            }
        }
    }

    @Published public private(set) var phase: Phase = .idle
    @Published public private(set) var connectedSpeakers: [DeviceInfo] = []
    @Published public private(set) var statusText = L10n.text("phase.idle")
    @Published public private(set) var lastError: String?
    @Published public private(set) var bestRTT: TimeInterval?
    @Published public private(set) var isPaused = false
    @Published public private(set) var isStreamingSystemAudio = false
    /// Bumps when a local track finishes naturally so UI can auto-advance.
    @Published public private(set) var finishedTrackToken = UUID()

    public let localDevice: DeviceInfo
    private var connections: [SyncConnection] = []
    private var audioConnections: [SyncConnection] = []
    /// Explicit control/audio pairing. Labels are not a reliable identity when
    /// multiple phones connect through the same hotspot or reconnect quickly.
    private var audioByControl: [ObjectIdentifier: SyncConnection] = [:]
    private var controlByAudio: [ObjectIdentifier: SyncConnection] = [:]
    private var speakerConnections: [String: SyncConnection] = [:]
    private var synchronizers: [ObjectIdentifier: ClockSynchronizer] = [:]
    private var clockTimers: [ObjectIdentifier: Timer] = [:]
    private var adaptiveLeadTime = AdaptiveLeadTime()
    private let chunker = AudioChunker(samplesPerChunk: 2048)
    /// File playback can use larger chunks than live capture. This halves
    /// Network/AVAudioPlayerNode scheduling pressure on older phones.
    private let fileChunker = AudioChunker(samplesPerChunk: 4096)
    private var currentSessionID: UUID?
    private var localPlayer: SyncAudioPlayer?
    private var audioStreamTask: Task<Void, Never>?
    private var pendingStopSessionIDs: Set<UUID> = []
    private var pausedStopSessionIDs: Set<UUID> = []
    private var pausedTrack: DecodedTrack?
    private var currentTrack: DecodedTrack?
    private var currentTrackStartAt: TimeInterval?
    private var playsLocally = false
    #if os(macOS)
    private var blackHoleCapture: BlackHoleAudioCapture?
    private var liveOutputDeviceID: AudioDeviceID?
    private var previousSystemOutputDevice: AudioDeviceID?
    private var previousSystemInputDevice: AudioDeviceID?
    private var liveSessionID: UUID?
    private var liveHostPlayAt: TimeInterval?
    private var liveSampleRate: Double = SyncProtocol.sampleRate
    private var liveSamples: [Float] = []
    private var liveSequence: UInt64 = 0
    private var liveSampleIndex: UInt64 = 0
    private var liveChunkQueue: [(AudioChunkHeader, Data)] = []
    private var liveSendTask: Task<Void, Never>?
    #endif

    public init(deviceName: String? = nil) {
        let resolvedName = deviceName ?? Self.defaultHostName()
        #if os(macOS)
        let platform: String? = "macos"
        #elseif os(iOS)
        let platform: String? = "ios"
        #else
        let platform: String? = nil
        #endif
        localDevice = DeviceInfo(
            id: UUID().uuidString,
            name: resolvedName,
            role: .host,
            platform: platform
        )
    }

    public func connect(to peer: DiscoveredPeer) {
        if connections.contains(where: { $0.remoteLabel == peer.endpointDebug }) {
            return
        }
        statusText = "正在连接 \(peer.name)…"
        if !hasActivePlaybackSession {
            phase = .connected
        }
        let control = NWConnection(to: peer.nwEndpoint, using: .tcp)
        let audio = NWConnection(to: peer.nwEndpoint, using: .tcp)
        attach(
            SyncConnection(connection: control, remoteLabel: peer.endpointDebug),
            audio: SyncConnection(connection: audio, remoteLabel: "\(peer.endpointDebug)-audio"),
            displayName: peer.name
        )
    }

    /// Connect every discovered peer that is not already linked.
    public func connectAll(to peers: [DiscoveredPeer]) {
        let pending = peers.filter { peer in
            !connections.contains(where: { $0.remoteLabel == peer.endpointDebug })
        }
        guard !pending.isEmpty else { return }
        statusText = L10n.format("status.connecting.all", pending.count)
        if !hasActivePlaybackSession {
            phase = .connected
        }
        lastError = nil
        for peer in pending {
            connect(to: peer)
        }
    }

    private var hasActivePlaybackSession: Bool {
        currentSessionID != nil && (phase == .playing || isStreamingSystemAudio || currentTrack != nil)
    }

    /// Manual LAN connect when Bonjour discovery is blocked.
    public func connect(host: String, port: UInt16 = SyncBonjour.controlPort) {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastError = L10n.text("error.enter.ip")
            return
        }
        let label = "\(trimmed):\(port)"
        if connections.contains(where: { $0.remoteLabel == label }) {
            return
        }

        if ConnectFailureText.likelyDifferentSubnet(local: LocalNetworkAddress.primaryIPv4(), remote: trimmed) {
            lastError = L10n.text("network.warn.subnet")
        } else if LocalNetworkAddress.vpnInterfacesPresent() {
            lastError = L10n.text("network.warn.vpn")
        } else {
            lastError = nil
        }

        statusText = L10n.format("status.connecting.to", label)
        if !hasActivePlaybackSession {
            phase = .connected
        }
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

    public func isConnected(endpointLabel: String) -> Bool {
        connections.contains { $0.remoteLabel == endpointLabel }
    }

    public func disconnect(_ speaker: DeviceInfo) {
        guard let connection = speakerConnections[speaker.id] else { return }
        disconnect(connection, speakerID: speaker.id)
    }

    public func disconnect(endpointLabel: String) {
        guard let connection = connections.first(where: { $0.remoteLabel == endpointLabel }) else { return }
        let speakerID = speakerConnections.first(where: { $0.value === connection })?.key
        disconnect(connection, speakerID: speakerID)
    }

    private func disconnect(_ connection: SyncConnection, speakerID: String?) {
        connection.sendControl(.goodbye(deviceID: localDevice.id))
        removePairedAudio(for: connection)
        connection.cancel()
        remove(connection, reason: "已断开")
        if let speakerID {
            speakerConnections[speakerID] = nil
            connectedSpeakers.removeAll { $0.id == speakerID }
        }
        phase = connections.isEmpty ? .idle : .ready
        statusText = "已断开设备"
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
        audioByControl[ObjectIdentifier(control)] = audio
        controlByAudio[ObjectIdentifier(audio)] = control
        audio.start { [weak self] event in
            Task { @MainActor in
                self?.handleAudioChannel(event, from: audio)
            }
        }
    }

    public func play(track: DecodedTrack, alsoPlayLocally: Bool) {
        let hasRemoteOutput = !connections.isEmpty && !audioConnections.isEmpty
        guard hasRemoteOutput || alsoPlayLocally else {
            lastError = L10n.text("error.no.speakers")
            phase = .error
            return
        }

        // Finish the previous session cleanly so speakers flush old audio/engine
        // state before the next prepare — critical for playlist auto-advance sync.
        if let previous = currentSessionID {
            pendingStopSessionIDs.remove(previous)
            pausedStopSessionIDs.remove(previous)
            broadcast(.stopPlayback(sessionID: previous))
        }
        audioStreamTask?.cancel()
        audioStreamTask = nil
        localPlayer?.stop()
        localPlayer = nil

        isPaused = false
        pausedTrack = nil
        currentTrack = track
        playsLocally = alsoPlayLocally
        let sessionID = UUID()
        currentSessionID = sessionID
        let prepare = PrepareSession(sessionID: sessionID, sampleRate: track.sampleRate, channels: 1, title: track.title)
        broadcast(.prepareSession(prepare))
        phase = .syncingClock
        statusText = "正在准备：\(track.title)"

        let recipients = audioConnections
        audioStreamTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // Speakers rebuild AVAudioEngine on prepare; give them enough time
            // before we freeze hostPlayAt and push audio.
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled, self.currentSessionID == sessionID else { return }

            // Prepare Mac local output during settle window so schedule isn't late.
            // Never abort the whole remote session if local output fails.
            var preparedLocal: SyncAudioPlayer?
            if alsoPlayLocally {
                let player = SyncAudioPlayer(sampleRate: track.sampleRate)
                do {
                    #if os(macOS)
                    if let output = AudioDeviceList.builtInOutput() {
                        try AudioDeviceList.setDefaultOutput(output.id)
                        try player.setOutputDevice(output.id)
                        try await player.prepareSession(sampleRate: track.sampleRate)
                        guard self.currentSessionID == sessionID else {
                            player.stop()
                            return
                        }
                        preparedLocal = player
                    } else {
                        self.lastError = L10n.text("error.output.missing")
                    }
                    #else
                    try await player.prepareSession(sampleRate: track.sampleRate)
                    guard self.currentSessionID == sessionID else {
                        player.stop()
                        return
                    }
                    preparedLocal = player
                    #endif
                } catch {
                    self.lastError = error.localizedDescription
                }
            }

            guard !Task.isCancelled, self.currentSessionID == sessionID else {
                preparedLocal?.stop()
                return
            }

            // Keep enough runway for a weaker second phone without changing
            // relative synchronization between devices.
            let lead = max(self.adaptiveLeadTime.recommendedLeadTime, 1.4)
            let hostPlayAt = HostTime.now() + lead
            self.currentTrackStartAt = hostPlayAt
            self.broadcast(.startPlayback(StartPlayback(
                sessionID: sessionID,
                hostPlayAt: hostPlayAt,
                leadTime: lead
            )))
            if let preparedLocal {
                self.localPlayer = preparedLocal
                preparedLocal.schedule(pcm: track.pcmFloat32Mono, playAtLocalUptime: hostPlayAt)
            }
            self.phase = .playing
            self.statusText = "播放中：\(track.title)"

            let chunks = self.fileChunker.chunks(from: track, sessionID: sessionID, hostPlayAtZero: hostPlayAt)
            let targetBufferedAudio = min(max(1.1, lead * 0.9), 1.3)
            // Each speaker gets an independent paced stream. A temporary TCP
            // back-pressure event on one phone must not stall every other phone.
            await withTaskGroup(of: Void.self) { group in
                for connection in recipients {
                    group.addTask {
                        await Self.stream(
                            chunks,
                            to: connection,
                            targetBufferedAudio: targetBufferedAudio
                        )
                    }
                }
            }

            let endAt = hostPlayAt + track.duration
            let remaining = endAt - HostTime.now()
            if remaining > 0 {
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }
            guard self.currentSessionID == sessionID, !Task.isCancelled else { return }
            // Tell speakers the session ended before auto-next prepare arrives.
            self.broadcast(.stopPlayback(sessionID: sessionID))
            self.audioStreamTask = nil
            self.currentSessionID = nil
            self.currentTrack = nil
            self.currentTrackStartAt = nil
            self.localPlayer?.stop()
            self.localPlayer = nil
            self.phase = self.connectedSpeakers.isEmpty ? .idle : .ready
            self.statusText = L10n.text("status.track.finished")
            self.finishedTrackToken = UUID()
        }
    }

    private nonisolated static func stream(
        _ chunks: [(AudioChunkHeader, Data)],
        to connection: SyncConnection,
        targetBufferedAudio: TimeInterval
    ) async {
        for (header, pcm) in chunks {
            guard !Task.isCancelled else { return }
            let wait = header.hostPlayAt - HostTime.now() - targetBufferedAudio
            if wait > 0 {
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            await connection.sendAudio(header: header, pcm: pcm)
        }
    }

    public func stop() {
        #if os(macOS)
        stopSystemAudioCapture()
        #endif
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

    #if os(macOS)
    /// Routes BlackHole input through one shared delay timeline to Mac and speakers.
    public func startUnifiedSystemAudioStreaming() async {
        let microphoneAuthorized: Bool
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphoneAuthorized = true
        case .notDetermined:
            microphoneAuthorized = await AVCaptureDevice.requestAccess(for: .audio)
        default:
            microphoneAuthorized = false
        }
        guard microphoneAuthorized else {
            lastError = L10n.text("error.microphone.permission")
            phase = .error
            return
        }

        guard !connections.isEmpty, !audioConnections.isEmpty else {
            lastError = L10n.text("error.no.speakers")
            phase = .error
            return
        }
        guard let blackHole = AudioDeviceList.blackHoleInput() else {
            lastError = L10n.text("error.blackhole.missing")
            phase = .error
            return
        }
        guard let output = AudioDeviceList.builtInOutput() else {
            lastError = L10n.text("error.output.missing")
            phase = .error
            return
        }

        stop()
        do {
            previousSystemOutputDevice = AudioDeviceList.defaultOutputID()
            previousSystemInputDevice = AudioDeviceList.defaultInputID()
            try AudioDeviceList.setDefaultOutput(blackHole.id)
            try AudioDeviceList.setDefaultInput(blackHole.id)
            liveOutputDeviceID = output.id

            // Switching the system devices is asynchronous. A fresh
            // AVAudioEngine can briefly fail with AVFAudio -10868 while Core
            // Audio is still reconfiguring after a previous live session.
            var capture: BlackHoleAudioCapture?
            var lastStartError: Error?
            for attempt in 0..<3 {
                let candidate = BlackHoleAudioCapture()
                candidate.onSamples = { [weak self] samples, sampleRate in
                    self?.appendLiveSamples(samples, sampleRate: sampleRate)
                }
                do {
                    try candidate.start(deviceID: blackHole.id)
                    capture = candidate
                    break
                } catch {
                    candidate.stop()
                    lastStartError = error
                    if attempt < 2 {
                        try? await Task.sleep(nanoseconds: 350_000_000)
                    }
                }
            }
            guard let capture else {
                throw lastStartError ?? NSError(
                    domain: "Chorus.BlackHole",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "无法启动 BlackHole 音频采集"]
                )
            }
            blackHoleCapture = capture
            isStreamingSystemAudio = true
            phase = .ready
            statusText = "正在等待 BlackHole 系统音频…"
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard let self,
                      self.isStreamingSystemAudio,
                      self.liveSessionID == nil
                else {
                    return
                }
                self.statusText = "未收到 BlackHole 音频。请确认系统输出是“仅 BlackHole 2ch”，并播放一段声音。"
            }
        } catch {
            restoreSystemAudioDevices()
            liveOutputDeviceID = nil
            lastError = error.localizedDescription
            phase = .error
        }
    }

    private func beginLiveSession(sampleRate: Double) {
        let sessionID = UUID()
        let lead = adaptiveLeadTime.recommendedLeadTime
        let hostPlayAt = HostTime.now() + lead

        liveSessionID = sessionID
        liveHostPlayAt = hostPlayAt
        liveSampleRate = sampleRate
        liveSamples.removeAll(keepingCapacity: true)
        liveSequence = 0
        liveSampleIndex = 0
        liveChunkQueue.removeAll(keepingCapacity: true)
        currentSessionID = sessionID
        currentTrack = nil
        currentTrackStartAt = hostPlayAt
        isPaused = false

        #if os(macOS)
        if let outputDeviceID = liveOutputDeviceID {
            let player = SyncAudioPlayer(sampleRate: sampleRate)
            localPlayer = player
            Task { @MainActor in
                do {
                    try player.setOutputDevice(outputDeviceID)
                    try await player.prepareSession(sampleRate: sampleRate)
                    guard self.currentSessionID == sessionID else { return }
                } catch {
                    self.lastError = "无法启动 Mac 本地回放：\(error.localizedDescription)"
                    self.localPlayer = nil
                }
            }
        }
        #endif
        broadcast(.prepareSession(PrepareSession(
            sessionID: sessionID,
            sampleRate: sampleRate,
            channels: SyncProtocol.channels,
            title: "Mac 系统音频"
        )))
        broadcast(.startPlayback(StartPlayback(
            sessionID: sessionID,
            hostPlayAt: hostPlayAt,
            leadTime: lead
        )))
        phase = .playing
        statusText = "正在转播 Mac 系统声音"
    }

    private func appendLiveSamples(_ samples: [Float], sampleRate: Double) {
        guard isStreamingSystemAudio else { return }
        if liveSessionID == nil {
            beginLiveSession(sampleRate: sampleRate)
        }
        guard let sessionID = liveSessionID,
              let hostPlayAt = liveHostPlayAt
        else {
            return
        }

        liveSamples.append(contentsOf: samples)
        let samplesPerChunk = chunker.samplesPerChunk
        while liveSamples.count >= samplesPerChunk {
            let chunk = Array(liveSamples.prefix(samplesPerChunk))
            liveSamples.removeFirst(samplesPerChunk)
            let pcm = chunk.withUnsafeBufferPointer { Data(buffer: $0) }
            let header = AudioChunkHeader(
                sessionID: sessionID,
                sequence: liveSequence,
                sampleIndex: liveSampleIndex,
                sampleCount: UInt32(samplesPerChunk),
                hostPlayAt: hostPlayAt + Double(liveSampleIndex) / liveSampleRate
            )
            liveChunkQueue.append((header, pcm))
            localPlayer?.scheduleChunk(pcmData: pcm, playAtLocalUptime: header.hostPlayAt)
            liveSequence += 1
            liveSampleIndex += UInt64(samplesPerChunk)
        }
        drainLiveChunkQueue()
    }

    private func drainLiveChunkQueue() {
        guard liveSendTask == nil else { return }
        liveSendTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self,
                      let frame = self.liveChunkQueue.first,
                      frame.0.sessionID == self.liveSessionID
                else {
                    break
                }
                self.liveChunkQueue.removeFirst()
                // Refresh recipients every frame so mid-session joiners get PCM.
                let recipients = self.audioConnections
                for connection in recipients {
                    guard !Task.isCancelled else { return }
                    await connection.sendAudio(header: frame.0, pcm: frame.1)
                }
            }
            self?.liveSendTask = nil
            if self?.liveChunkQueue.isEmpty == false {
                self?.drainLiveChunkQueue()
            }
        }
    }

    private func stopSystemAudioCapture() {
        guard isStreamingSystemAudio || blackHoleCapture != nil else { return }
        blackHoleCapture?.stop()
        blackHoleCapture = nil
        restoreSystemAudioDevices()
        isStreamingSystemAudio = false
        liveSessionID = nil
        liveHostPlayAt = nil
        liveSampleRate = SyncProtocol.sampleRate
        liveOutputDeviceID = nil
        liveSamples.removeAll(keepingCapacity: false)
        liveChunkQueue.removeAll(keepingCapacity: false)
        liveSendTask?.cancel()
        liveSendTask = nil
    }

    private func restoreSystemAudioDevices() {
        if let previousSystemOutputDevice {
            try? AudioDeviceList.setDefaultOutput(previousSystemOutputDevice)
        }
        if let previousSystemInputDevice {
            try? AudioDeviceList.setDefaultInput(previousSystemInputDevice)
        }
        previousSystemOutputDevice = nil
        previousSystemInputDevice = nil
    }
    #endif

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
        phase = .ready
        statusText = isPaused ? "已暂停" : "已播放完毕"
    }

    public func resume() {
        guard let pausedTrack else { return }
        play(track: pausedTrack, alsoPlayLocally: playsLocally)
    }

    private func requestStop(sessionID: UUID) {
        // Local-only playback has nobody to acknowledge a stop.
        guard !connections.isEmpty else { return }
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
        audioByControl.removeAll()
        controlByAudio.removeAll()
        speakerConnections.removeAll()
        connectedSpeakers.removeAll()
        synchronizers.removeAll()
        phase = .idle
        statusText = L10n.text("phase.idle")
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
            let audioKey = ObjectIdentifier(connection)
            if let control = controlByAudio.removeValue(forKey: audioKey) {
                audioByControl[ObjectIdentifier(control)] = nil
                // Detach only this speaker. Playback and the independent streams
                // for all remaining speakers must continue.
                control.cancel()
                remove(control, reason: L10n.text("error.audio.channel"))
            }
        case .control, .audio:
            break
        }
    }

    private func handleControl(_ payload: ControlPayload, from connection: SyncConnection) {
        switch payload {
        case .hello(let info):
            speakerConnections[info.id] = connection
            if !connectedSpeakers.contains(where: { $0.id == info.id }) {
                connectedSpeakers.append(info)
            }
            connection.sendControl(.welcome(localDevice))
            admitSpeakerAfterHandshake(connection, name: info.name)
        case .welcome(let info):
            speakerConnections[info.id] = connection
            if !connectedSpeakers.contains(where: { $0.id == info.id }) {
                connectedSpeakers.append(info)
            }
            admitSpeakerAfterHandshake(connection, name: info.name)
        case .clockPong(let pong):
            let syncer = synchronizers[ObjectIdentifier(connection)]
            syncer?.recordPong(pong, hostReceiveTime: HostTime.now())
            bestRTT = syncer?.bestEstimate?.roundTrip
            if let offset = syncer?.bestEstimate?.offset {
                connection.sendControl(.clockOffset(seconds: offset))
            }
            if let bestRTT {
                adaptiveLeadTime.record(roundTrip: bestRTT)
            }
            if let rtt = bestRTT,
               rtt < 0.08,
               phase != .playing,
               !isPaused,
               !isStreamingSystemAudio {
                phase = .ready
                statusText = "就绪（RTT ≈ \(Int(rtt * 1000)) ms）"
            }
        case .goodbye(let id):
            if let connection = speakerConnections[id] {
                removePairedAudio(for: connection)
                connection.cancel()
                remove(connection, reason: "扬声器已退出同步")
                speakerConnections[id] = nil
            }
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

    private func admitSpeakerAfterHandshake(_ connection: SyncConnection, name: String) {
        if hasActivePlaybackSession {
            statusText = "中途加入：\(name)，正在同步…"
            scheduleLateJoinCatchUp(for: connection, speakerName: name)
        } else {
            phase = .syncingClock
            statusText = "已连接 \(name)，校准时钟…"
        }
    }

    /// When a speaker joins mid-playback / live stream: wait for clock, then unicast prepare+start
    /// on the original timeline so they can join without a full stop/restart.
    private func scheduleLateJoinCatchUp(for connection: SyncConnection, speakerName: String) {
        guard let sessionID = currentSessionID,
              let hostPlayAt = currentTrackStartAt ?? liveHostPlayAt
        else { return }

        #if os(macOS)
        let sampleRate = currentTrack?.sampleRate ?? liveSampleRate
        #else
        let sampleRate = currentTrack?.sampleRate ?? SyncProtocol.sampleRate
        #endif
        let title = currentTrack?.title
            ?? (isStreamingSystemAudio ? "Mac 系统音频" : "Session")
        let track = currentTrack
        let lead = max(adaptiveLeadTime.recommendedLeadTime, 1.4)

        Task { @MainActor [weak self] in
            guard let self else { return }
            for _ in 0..<25 {
                if Task.isCancelled { return }
                if self.synchronizers[ObjectIdentifier(connection)]?.bestEstimate != nil { break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            guard self.currentSessionID == sessionID else { return }

            // Wait for audio channel pairing before prepare so early PCM isn't dropped.
            for _ in 0..<20 {
                if self.audioByControl[ObjectIdentifier(connection)] != nil { break }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            guard self.currentSessionID == sessionID else { return }

            connection.sendControl(.prepareSession(PrepareSession(
                sessionID: sessionID,
                sampleRate: sampleRate,
                channels: SyncProtocol.channels,
                title: title
            )))
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard self.currentSessionID == sessionID else { return }

            connection.sendControl(.startPlayback(StartPlayback(
                sessionID: sessionID,
                hostPlayAt: hostPlayAt,
                leadTime: lead
            )))

            // File/demo: existing stream tasks don't include this socket — push remaining chunks.
            if let track {
                guard let audio = self.audioByControl[ObjectIdentifier(connection)],
                      self.currentSessionID == sessionID
                else { return }
                let chunks = self.fileChunker.chunks(
                    from: track,
                    sessionID: sessionID,
                    hostPlayAtZero: hostPlayAt
                )
                let fromTime = HostTime.now() - 0.35
                let remaining = chunks.filter { $0.0.hostPlayAt >= fromTime }
                let targetBufferedAudio = min(max(1.1, lead * 0.9), 1.3)
                Task {
                    await Self.stream(remaining, to: audio, targetBufferedAudio: targetBufferedAudio)
                }
            }

            if self.phase != .playing {
                self.phase = .playing
            }
            if self.isStreamingSystemAudio {
                self.statusText = "正在转播 Mac 系统声音（已同步 \(speakerName)）"
            } else {
                self.statusText = "播放中：\(title)（已同步 \(speakerName)）"
            }
        }
    }

    private func startClockPings(for connection: SyncConnection) {
        let key = ObjectIdentifier(connection)
        clockTimers[key]?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak connection] _ in
            guard let connection else { return }
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
        removePairedAudio(for: connection)
        connections.removeAll { $0 === connection }
        let disconnectedIDs = speakerConnections
            .filter { $0.value === connection }
            .map(\.key)
        disconnectedIDs.forEach { speakerConnections[$0] = nil }
        connectedSpeakers.removeAll { disconnectedIDs.contains($0.id) }
        if connections.isEmpty {
            connectedSpeakers.removeAll()
            if currentSessionID != nil {
                // Device connectivity must not invalidate local playback controls.
                phase = .playing
                statusText = playsLocally ? "设备已断开，本机继续播放" : "设备已断开"
                return
            }
            if isPaused {
                phase = .ready
                statusText = "已暂停"
                return
            }
            phase = .idle
            // No hello/welcome yet → treat as LAN reachability failure (common on locked-down Wi‑Fi).
            let failedBeforeHandshake = disconnectedIDs.isEmpty
            if failedBeforeHandshake, let reason, !reason.isEmpty {
                let mapped = ConnectFailureText.describe(reason)
                lastError = mapped
                statusText = L10n.format("status.connect.failed", mapped)
            } else {
                statusText = reason.map { L10n.format("status.disconnected.reason", $0) }
                    ?? L10n.text("status.disconnected")
            }
        }
    }

    private func removePairedAudio(for control: SyncConnection) {
        let controlKey = ObjectIdentifier(control)
        guard let audio = audioByControl.removeValue(forKey: controlKey) else { return }
        controlByAudio[ObjectIdentifier(audio)] = nil
        audioConnections.removeAll { $0 === audio }
        audio.cancel()
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
