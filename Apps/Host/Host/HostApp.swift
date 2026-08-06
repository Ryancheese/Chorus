import SwiftUI
import ChorusCore
import UniformTypeIdentifiers

@main
struct HostApp: App {
    var body: some Scene {
        WindowGroup {
            HostRootView()
                .frame(minWidth: 640, minHeight: 700)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

struct HostRootView: View {
    @StateObject private var browser = PeerBrowser()
    @StateObject private var session = HostSessionController()
    @StateObject private var languageSettings = LanguageSettings()
    @StateObject private var appearanceSettings = AppearanceSettings()
    @State private var selectedFileName: String?
    @State private var loadedTrack: DecodedTrack?
    @State private var playLocally = true
    @State private var isImporterPresented = false
    @State private var appeared = false
    @State private var isHelpPresented = false
    @State private var manualHost = ""
    @State private var manualPort = String(SyncBonjour.controlPort)

    private var canPlay: Bool {
        loadedTrack != nil && !session.connectedSpeakers.isEmpty && !session.isStreamingSystemAudio
    }

    private var isLive: Bool {
        session.phase == .playing || session.phase == .ready || session.phase == .syncingClock
    }

    var body: some View {
        let _ = languageSettings.selection
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
        .sheet(isPresented: $isHelpPresented) {
            ChorusHelpView(role: .host)
                .frame(minWidth: 520, minHeight: 460)
        }
        .chorusAppearance(appearanceSettings)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            PulsingOrb(isActive: isLive, symbol: session.phase == .playing ? "speaker.wave.3.fill" : "dot.radiowaves.left.and.right")

            VStack(alignment: .leading, spacing: 6) {
                Text("Chorus")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(L10n.text("host.tagline"))
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
            Button {
                isHelpPresented = true
            } label: {
                Label(L10n.text("action.help"), systemImage: "questionmark.circle")
            }
            .buttonStyle(GlassSecondaryButtonStyle())
            LanguageMenu(settings: languageSettings)
                .buttonStyle(GlassSecondaryButtonStyle())
            AppearanceMenu(settings: appearanceSettings)
                .buttonStyle(GlassSecondaryButtonStyle())
        }
    }

    private var statusPanel: some View {
        GlassPanel {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(session.phase.displayName)
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .foregroundStyle(.primary)
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
                sectionTitle(L10n.text("section.nearby"), systemImage: "iphone.gen3")

                Text(browser.statusText)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)

                if let error = browser.lastError {
                    Text(error)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.red.opacity(0.85))
                }

                if browser.peers.isEmpty {
                    emptyHint(L10n.text("hint.discovery"))
                } else {
                    ForEach(browser.peers) { peer in
                        peerRow(peer)
                    }
                }

                Divider().opacity(0.25)

                sectionTitle(L10n.text("section.manual.connect"), systemImage: "keyboard")
                HStack(spacing: 10) {
                    TextField(L10n.text("field.phone.ip"), text: $manualHost)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 180)
                    TextField(L10n.text("field.port"), text: $manualPort)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 72)
                    let endpointLabel = "\(manualHost.trimmingCharacters(in: .whitespacesAndNewlines)):\(UInt16(manualPort) ?? SyncBonjour.controlPort)"
                    Button(session.isConnected(endpointLabel: endpointLabel) ? L10n.text("action.disconnect") : L10n.text("action.connect")) {
                        let port = UInt16(manualPort) ?? SyncBonjour.controlPort
                        if session.isConnected(endpointLabel: endpointLabel) {
                            session.disconnect(endpointLabel: endpointLabel)
                        } else {
                            session.connect(host: manualHost, port: port)
                        }
                    }
                    .buttonStyle(GlassSecondaryButtonStyle())
                    .disabled(manualHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Divider().opacity(0.25)

                sectionTitle(L10n.text("section.session"), systemImage: "hifispeaker.fill")

                if session.connectedSpeakers.isEmpty {
                    emptyHint(L10n.text("hint.connect"))
                } else {
                    ForEach(session.connectedSpeakers) { speaker in
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(GlassTheme.mint)
                            Text(speaker.name)
                                .font(.system(.body, design: .rounded).weight(.medium))
                            Spacer()
                            Text(L10n.text("phase.ready"))
                                .font(.system(.caption, design: .rounded).weight(.semibold))
                                .foregroundStyle(.secondary)
                            Button(L10n.text("action.remove")) {
                                session.disconnect(speaker)
                            }
                            .buttonStyle(GlassSecondaryButtonStyle())
                        }
                    }
                }
            }
        }
    }

    private var playbackPanel: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 16) {
                sectionTitle(L10n.text("section.playback"), systemImage: "play.circle.fill")

                Toggle(isOn: $playLocally) {
                    Text(L10n.text("toggle.play.locally"))
                        .font(.system(.body, design: .rounded))
                }
                .tint(GlassTheme.accent)

                HStack(spacing: 10) {
                    Button(L10n.text("action.choose.audio")) { isImporterPresented = true }
                        .buttonStyle(GlassSecondaryButtonStyle())
                    Button(L10n.text("action.test.tone")) {
                        let track = DemoTone.makeTrack()
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            loadedTrack = track
                            selectedFileName = track.title
                        }
                    }
                    .buttonStyle(GlassSecondaryButtonStyle())
                    .disabled(session.isStreamingSystemAudio)

                    Button(session.isStreamingSystemAudio ? L10n.text("action.stream.system.stop") : L10n.text("action.stream.system.start")) {
                        if session.isStreamingSystemAudio {
                            session.stop()
                        } else {
                            Task {
                                await session.startUnifiedSystemAudioStreaming()
                            }
                        }
                    }
                    .buttonStyle(GlassSecondaryButtonStyle())
                    .disabled(!session.isStreamingSystemAudio && session.connectedSpeakers.isEmpty)

                    if let name = selectedFileName {
                        Text(name)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .transition(.opacity.combined(with: .move(edge: .leading)))
                    }
                }

                HStack(spacing: 12) {
                    Button(L10n.text("action.sync.play")) {
                        guard let track = loadedTrack else { return }
                        session.play(track: track, alsoPlayLocally: playLocally)
                    }
                    .buttonStyle(GlassPrimaryButtonStyle(enabled: canPlay))
                    .disabled(!canPlay)

                    Button(session.isPaused ? L10n.text("action.resume") : L10n.text("action.pause")) {
                        if session.isPaused {
                            session.resume()
                        } else {
                            session.pause()
                        }
                    }
                    .buttonStyle(GlassSecondaryButtonStyle())
                    .disabled(session.isStreamingSystemAudio || (session.phase != .playing && !session.isPaused))

                    Button(L10n.text("action.stop")) { session.stop() }
                        .buttonStyle(GlassSecondaryButtonStyle())
                        .disabled(session.phase != .playing && !session.isPaused)
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
            if session.isConnected(endpointLabel: peer.endpointDebug) {
                Button(L10n.text("action.disconnect")) {
                    session.disconnect(endpointLabel: peer.endpointDebug)
                }
                .buttonStyle(GlassSecondaryButtonStyle())
            } else {
                Button(L10n.text("action.connect")) {
                    session.connect(to: peer)
                }
                .buttonStyle(GlassSecondaryButtonStyle())
            }
        }
    }

    private func sectionTitle(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(.headline, design: .rounded))
            .foregroundStyle(.primary)
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
