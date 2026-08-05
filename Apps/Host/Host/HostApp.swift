import SwiftUI
import StereoSyncCore
import UniformTypeIdentifiers

@main
struct HostApp: App {
    var body: some Scene {
        WindowGroup {
            HostRootView()
                .frame(minWidth: 640, minHeight: 620)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

struct HostRootView: View {
    @StateObject private var browser = PeerBrowser()
    @StateObject private var session = HostSessionController()
    @State private var selectedFileName: String?
    @State private var loadedTrack: DecodedTrack?
    @State private var playLocally = true
    @State private var isImporterPresented = false
    @State private var connectedEndpoints: Set<String> = []
    @State private var appeared = false

    private var canPlay: Bool {
        loadedTrack != nil && !session.connectedSpeakers.isEmpty
    }

    private var isLive: Bool {
        session.phase == .playing || session.phase == .ready || session.phase == .syncingClock
    }

    var body: some View {
        ZStack {
            LiquidGlassBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    statusPanel
                    devicesPanel
                    playbackPanel
                }
                .padding(28)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
            }
        }
        .onAppear {
            browser.start()
            withAnimation(.spring(response: 0.7, dampingFraction: 0.86)) {
                appeared = true
            }
        }
        .onDisappear {
            browser.stop()
            session.teardown()
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            PulsingOrb(isActive: isLive, symbol: session.phase == .playing ? "speaker.wave.3.fill" : "dot.radiowaves.left.and.right")

            VStack(alignment: .leading, spacing: 6) {
                Text("StereoSync")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(GlassTheme.brand)
                Text("把 Mac 的声音，同步到身边的 iPhone 与 iPad")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    private var statusPanel: some View {
        GlassPanel {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(session.phase.rawValue)
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .foregroundStyle(GlassTheme.brand)
                    Text(session.statusText)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                    if let error = session.lastError {
                        Text(error)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.red.opacity(0.85))
                    }
                }
                Spacer(minLength: 0)
                if let rtt = session.bestRTT {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("RTT")
                            .font(.system(.caption2, design: .rounded).weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.0f ms", rtt * 1000))
                            .font(.system(.title2, design: .rounded).weight(.semibold))
                            .foregroundStyle(GlassTheme.accent)
                            .contentTransition(.numericText())
                    }
                }
            }
        }
    }

    private var devicesPanel: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 16) {
                sectionTitle("附近扬声器", systemImage: "iphone.gen3")

                if browser.peers.isEmpty {
                    emptyHint("打开 iPhone / iPad 上的 StereoSync，点「开始广播」")
                } else {
                    ForEach(browser.peers) { peer in
                        peerRow(peer)
                    }
                }

                Divider().opacity(0.25)

                sectionTitle("已加入会话", systemImage: "hifispeaker.fill")

                if session.connectedSpeakers.isEmpty {
                    emptyHint("连接一台设备后即可同步播放")
                } else {
                    ForEach(session.connectedSpeakers) { speaker in
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(GlassTheme.mint)
                            Text(speaker.name)
                                .font(.system(.body, design: .rounded).weight(.medium))
                            Spacer()
                            Text("就绪")
                                .font(.system(.caption, design: .rounded).weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var playbackPanel: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 16) {
                sectionTitle("播放", systemImage: "play.circle.fill")

                Toggle(isOn: $playLocally) {
                    Text("本机同时播放")
                        .font(.system(.body, design: .rounded))
                }
                .tint(GlassTheme.accent)

                HStack(spacing: 10) {
                    Button("选择音频") { isImporterPresented = true }
                        .buttonStyle(GlassSecondaryButtonStyle())
                    Button("测试音调") {
                        let track = DemoTone.makeTrack()
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            loadedTrack = track
                            selectedFileName = track.title
                        }
                    }
                    .buttonStyle(GlassSecondaryButtonStyle())

                    if let name = selectedFileName {
                        Text(name)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .transition(.opacity.combined(with: .move(edge: .leading)))
                    }
                }

                HStack(spacing: 12) {
                    Button("同步播放") {
                        guard let track = loadedTrack else { return }
                        session.play(track: track, alsoPlayLocally: playLocally)
                    }
                    .buttonStyle(GlassPrimaryButtonStyle(enabled: canPlay))
                    .disabled(!canPlay)

                    Button("停止") { session.stop() }
                        .buttonStyle(GlassSecondaryButtonStyle())
                        .disabled(session.phase != .playing)
                }
            }
        }
    }

    private func peerRow(_ peer: DiscoveredPeer) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "wave.3.right.circle.fill")
                .font(.title3)
                .foregroundStyle(GlassTheme.accent)
            Text(peer.name)
                .font(.system(.body, design: .rounded).weight(.medium))
            Spacer()
            if connectedEndpoints.contains(peer.endpointDebug) {
                Text("已连接")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
            } else {
                Button("连接") {
                    session.connect(to: peer)
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        connectedEndpoints.insert(peer.endpointDebug)
                    }
                }
                .buttonStyle(GlassSecondaryButtonStyle())
            }
        }
    }

    private func sectionTitle(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(.headline, design: .rounded))
            .foregroundStyle(GlassTheme.brand.opacity(0.9))
            .labelStyle(.titleAndIcon)
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.system(.subheadline, design: .rounded))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let track = try AudioFileLoader.load(url: url)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                loadedTrack = track
                selectedFileName = track.title
            }
        } catch {
            selectedFileName = nil
            loadedTrack = nil
        }
    }
}
