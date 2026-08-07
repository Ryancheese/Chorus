import Foundation
import Network
import Combine

#if canImport(AVFoundation)
import AVFoundation
#endif
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

    public enum AudioDisruption: Equatable {
        case screenMirrored
        case audioInterrupted
        case audioUnavailable
        case audioRouteChanged

        public var message: String {
            switch self {
            case .screenMirrored: L10n.text("error.screen.mirrored")
            case .audioInterrupted: L10n.text("error.audio.interrupted")
            case .audioUnavailable: L10n.text("error.audio.unavailable")
            case .audioRouteChanged: L10n.text("error.audio.route")
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
    /// Non-nil when sync was aborted due to mirroring / speaker occupation; UI should alert.
    @Published public private(set) var audioDisruptionMessage: String?
    /// VPN / offline / no-LAN hint while advertising.
    @Published public private(set) var networkWarning: String?
    /// Media volume / ringer tips (e.g. volume too low).
    @Published public private(set) var audioOutputWarning: String?

    public let localDevice: DeviceInfo
    private let advertiser: PeerAdvertiser
    private let audioOutputMonitor = AudioOutputMonitor()
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
    private var audioGuardTokens: [NSObjectProtocol] = []
    private var audioOutputObservation: AnyCancellable?
    private var isAbortingForAudio = false

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
        audioOutputObservation = audioOutputMonitor.$warningText
            .receive(on: RunLoop.main)
            .sink { [weak self] text in
                self?.audioOutputWarning = text
            }
    }

    deinit {
        for token in audioGuardTokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    public func startAdvertising() {
        lastError = nil
        audioDisruptionMessage = nil
        audioOutputMonitor.start()
        audioOutputWarning = audioOutputMonitor.warningText
        advertiser.start()
        isAdvertising = true
        phase = .advertising
        refreshConnectionAddress()
        statusText = L10n.text("status.wait.host")
        installAudioGuards()
        syncFromAdvertiser()
        #if os(iOS)
        refreshAudioEnvironmentHint()
        #endif
    }

    public func clearAudioDisruptionMessage() {
        audioDisruptionMessage = nil
    }

    private func syncFromAdvertiser() {
        refreshConnectionAddress()
        isAdvertising = advertiser.isAdvertising
        // Once a Host session is live, advertiser blips (hotspot path changes)
        // should not overwrite the session UI with red network noise.
        let sessionLive = hostName != nil
            || phase == .connected
            || phase == .syncing
            || phase == .ready
            || phase == .playing
        if !sessionLive {
            lastError = advertiser.lastError
        }
        refreshNetworkWarning()
        if advertiser.isAdvertising, phase == .idle || phase == .error {
            phase = .advertising
            statusText = advertiser.bonjourUnavailable
                ? L10n.text("status.wait.manual")
                : L10n.text("status.wait.host")
        }
        if !advertiser.isAdvertising, let err = advertiser.lastError, phase == .advertising {
            phase = .error
            statusText = err
        }
    }

    public func stopAll() {
        removeAudioGuards()
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
        audioOutputMonitor.stop()
        isAdvertising = false
        connectionAddress = nil
        networkWarning = nil
        audioOutputWarning = nil
        phase = .idle
        statusText = L10n.text("status.stopped")
        hostName = nil
        sessionTitle = nil
    }

    private func refreshConnectionAddress() {
        let ip = advertiser.localIPv4
            ?? LocalNetworkAddress.primaryIPv4()
            ?? L10n.text("label.unknown.ip")
        connectionAddress = "\(ip):\(advertiser.listeningPort)"
    }

    private func refreshNetworkWarning() {
        // Hotspot host (bridge100 / 172.20.10.1) must never look like a VPN.
        if LocalNetworkAddress.isPersonalHotspotActive() {
            networkWarning = nil
            return
        }
        // Only the primary address on a tunnel counts — idle system utun* IPv4s don't.
        if LocalNetworkAddress.vpnInterfacesPresent() {
            networkWarning = L10n.text("network.warn.vpn")
            return
        }
        if LocalNetworkAddress.primaryIPv4() == nil {
            networkWarning = L10n.text("network.warn.no.lan")
            return
        }
        if advertiser.bonjourUnavailable {
            networkWarning = L10n.text("network.hint.bonjour.fallback")
            return
        }
        networkWarning = nil
    }

    private func accept(_ nw: NWConnection) {
        #if os(iOS)
        if let disruption = currentAudioBlocker() {
            nw.cancel()
            abortSync(for: disruption)
            return
        }
        #endif
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
            #if os(iOS)
            if let disruption = currentAudioBlocker() {
                sync.sendControl(.goodbye(deviceID: localDevice.id))
                sync.cancel()
                abortSync(for: disruption)
                return
            }
            #endif
            connection?.cancel()
            connection = sync
            hostName = info.name
            lastError = nil
            audioDisruptionMessage = nil
            connection?.sendControl(.welcome(localDevice))
            phase = .syncing
            statusText = "已连接 \(info.name)"
        case .welcome(let info):
            #if os(iOS)
            if let disruption = currentAudioBlocker() {
                abortSync(for: disruption)
                return
            }
            #endif
            hostName = info.name
            lastError = nil
            audioDisruptionMessage = nil
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
            #if os(iOS)
            if let disruption = currentAudioBlocker() {
                abortSync(for: disruption)
                return
            }
            #endif
            sessionID = session.sessionID
            lastStoppedSessionID = nil
            sessionTitle = session.title
            let prepareID = session.sessionID
            Task { @MainActor in
                do {
                    try await player.prepareSession(sampleRate: session.sampleRate)
                    // Ignore stale prepare if Host already moved on / retried.
                    guard self.sessionID == prepareID, sync === self.connection else { return }
                    #if os(iOS)
                    self.audioOutputMonitor.refresh()
                    // Activation can briefly change the reported route; re-check after.
                    if let disruption = self.currentAudioBlocker() {
                        self.abortSync(for: disruption)
                        return
                    }
                    #endif
                    self.jitterBuffer = AudioJitterBuffer(sampleRate: session.sampleRate)
                    self.lastError = nil
                    self.audioDisruptionMessage = nil
                    self.statusText = "准备播放：\(session.title)"
                    #if os(iOS)
                    self.audioOutputWarning = self.audioOutputMonitor.warningText
                    #endif
                } catch is CancellationError {
                    guard self.sessionID == prepareID, sync === self.connection else { return }
                    // Superseded by a newer prepare — keep waiting, don't scare the UI.
                } catch {
                    // A superseded prepare must not wipe an already-playing session.
                    guard self.sessionID == prepareID, sync === self.connection else { return }
                    self.abortSync(for: .audioUnavailable)
                }
            }
        case .startPlayback(let start):
            guard sync === connection, start.sessionID == sessionID else { return }
            #if os(iOS)
            if let disruption = currentAudioBlocker() {
                abortSync(for: disruption)
                return
            }
            #endif
            sessionID = start.sessionID
            playbackOffset = offset
            lastError = nil
            audioDisruptionMessage = nil
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
            audioDisruptionMessage = nil
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
            // Successful audio means any prior “speaker busy” tip is stale.
            lastError = nil
            audioDisruptionMessage = nil
            statusText = sessionTitle.map { "播放中：\($0)" } ?? "播放中"
        }
    }

    /// Tear down the host sync session, keep advertising, and surface a user-facing alert.
    private func abortSync(for disruption: AudioDisruption) {
        guard !isAbortingForAudio else { return }
        isAbortingForAudio = true
        defer { isAbortingForAudio = false }

        let message = disruption.message
        if let connection {
            connection.sendControl(.goodbye(deviceID: localDevice.id))
        }
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
        clockOffsetMs = nil

        lastError = message
        audioDisruptionMessage = message
        phase = advertiser.isAdvertising ? .advertising : .error
        isAdvertising = advertiser.isAdvertising
        statusText = message
        refreshConnectionAddress()
    }

    #if os(iOS)
    private var isInSyncSession: Bool {
        switch phase {
        case .connecting, .connected, .syncing, .ready, .playing:
            return true
        case .idle, .advertising, .error:
            return connection != nil || audioConnection != nil
        }
    }

    private var isScreenCaptured: Bool {
        UIScreen.main.isCaptured
    }

    /// Non-nil when the current environment cannot keep reliable phone-speaker sync.
    private func currentAudioBlocker() -> AudioDisruption? {
        if isScreenCaptured { return .screenMirrored }
        if hasExternalAudioOutput { return .audioRouteChanged }
        return nil
    }

    private var hasExternalAudioOutput: Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains { isExternalOutput($0.portType) }
    }

    private func isExternalOutput(_ port: AVAudioSession.Port) -> Bool {
        switch port {
        case .builtInSpeaker, .builtInReceiver:
            return false
        default:
            // Headphones, Bluetooth, AirPlay, CarPlay, USB, HDMI, etc.
            return true
        }
    }

    private func installAudioGuards() {
        removeAudioGuards()
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()

        audioGuardTokens.append(
            center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: session,
                queue: .main
            ) { [weak self] notification in
                Task { @MainActor in
                    self?.handleAudioInterruption(notification)
                }
            }
        )

        audioGuardTokens.append(
            center.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: session,
                queue: .main
            ) { [weak self] notification in
                Task { @MainActor in
                    self?.handleRouteChange(notification)
                }
            }
        )

        audioGuardTokens.append(
            center.addObserver(
                forName: UIScreen.capturedDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.handleScreenCaptureChange()
                }
            }
        )
    }

    private func removeAudioGuards() {
        for token in audioGuardTokens {
            NotificationCenter.default.removeObserver(token)
        }
        audioGuardTokens.removeAll()
    }

    private func handleAudioInterruption(_ notification: Notification) {
        guard isInSyncSession else { return }
        guard
            let info = notification.userInfo,
            let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue),
            type == .began
        else { return }
        abortSync(for: .audioInterrupted)
    }

    private func handleRouteChange(_ notification: Notification) {
        guard
            let info = notification.userInfo,
            let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
        else { return }

        switch reason {
        case .newDeviceAvailable, .oldDeviceUnavailable, .override:
            break
        default:
            // Ignore categoryChange from our own setActive/setCategory.
            refreshAudioEnvironmentHint()
            audioOutputMonitor.refresh()
            return
        }

        // Only abort when output actually left the built-in speaker/receiver.
        // Activating `.playback` often emits a route change that still ends on
        // the built-in speaker — aborting there causes false “无声/已退出”.
        if isInSyncSession {
            if hasExternalAudioOutput {
                abortSync(for: .audioRouteChanged)
            } else {
                audioOutputMonitor.refresh()
            }
        } else {
            refreshAudioEnvironmentHint()
            audioOutputMonitor.refresh()
        }
    }

    private func handleScreenCaptureChange() {
        if let disruption = currentAudioBlocker(), isInSyncSession {
            abortSync(for: disruption)
        } else {
            refreshAudioEnvironmentHint()
        }
    }

    private func refreshAudioEnvironmentHint() {
        guard phase == .advertising, connection == nil else { return }
        if isScreenCaptured {
            statusText = L10n.text("hint.screen.mirrored")
        } else if hasExternalAudioOutput {
            statusText = L10n.text("hint.audio.route.external")
        } else if advertiser.isAdvertising {
            statusText = advertiser.bonjourUnavailable
                ? "等待 Mac 手动连接…"
                : "等待 Mac 连接…"
        }
    }
    #else
    private func installAudioGuards() {}
    private func removeAudioGuards() {}
    #endif

    public static func defaultSpeakerName() -> String {
        #if os(iOS)
        return UIDevice.current.name
        #else
        return "Speaker"
        #endif
    }
}
