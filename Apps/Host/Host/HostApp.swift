import SwiftUI
import ChorusCore
import UniformTypeIdentifiers

@main
struct HostApp: App {
    var body: some Scene {
        WindowGroup {
            HostRootView()
                .frame(minWidth: 920, minHeight: 720)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

struct HostRootView: View {
    @StateObject private var browser = PeerBrowser()
    @StateObject private var session = HostSessionController()
    @StateObject private var network = NetworkCapabilityMonitor()
    @StateObject private var playlist = HostPlaylist()
    @StateObject private var languageSettings = LanguageSettings()
    @StateObject private var appearanceSettings = AppearanceSettings()
    @State private var playLocally = true
    @State private var isFileImporterPresented = false
    @State private var isFolderImporterPresented = false
    @State private var appeared = false
    @State private var isHelpPresented = false
    @State private var manualHost = ""
    @State private var manualPort = String(SyncBonjour.controlPort)
    @State private var playlistError: String?

    private var canPlay: Bool {
        playlist.currentItem != nil
            && (!session.connectedSpeakers.isEmpty || playLocally)
            && !session.isStreamingSystemAudio
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
            network.start()
            browser.start()
            withAnimation(.spring(response: 0.7, dampingFraction: 0.86)) {
                appeared = true
            }
        }
        .onDisappear {
            browser.stop()
            network.stop()
            session.teardown()
        }
        .onChange(of: session.finishedTrackToken) { _, _ in
            // Small gap so the previous stop/prepare settle can land on speakers
            // before decoding + starting the next playlist item.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000)
                playNextIfPossible()
            }
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            handleAudioImport(result)
        }
        .fileImporter(
            isPresented: $isFolderImporterPresented,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleFolderImport(result)
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

                if let warning = network.warningText {
                    networkBanner(warning)
                } else if let hint = browser.networkHint {
                    networkBanner(hint)
                }

                Text(browser.statusText)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)

                if let error = browser.lastError {
                    Text(error)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.red.opacity(0.85))
                }

                if browser.peers.isEmpty {
                    emptyHint(
                        browser.networkHint != nil
                            ? L10n.text("hint.discovery.restricted")
                            : L10n.text("hint.discovery")
                    )
                } else {
                    ForEach(browser.peers) { peer in
                        peerRow(peer)
                    }
                }

                Divider().opacity(0.25)

                sectionTitle(L10n.text("section.manual.connect"), systemImage: "keyboard")
                if let local = network.localIPv4 {
                    Text(L10n.format("hint.host.local.ip", local))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.secondary)
                }
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
                            Text(speaker.platformLabel)
                                .font(.system(.caption2, design: .rounded).weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.white.opacity(0.08), in: Capsule())
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

    private func networkBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(text)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        }
    }

    private var playbackPanel: some View {
        GlassPanel {
            HStack(alignment: .top, spacing: 20) {
                playbackControls
                    .frame(maxWidth: .infinity, alignment: .leading)

                Divider().opacity(0.3)

                playlistSidebar
                    .frame(width: 300, alignment: .topLeading)
            }
        }
    }

    private var playbackControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle(L10n.text("section.playback"), systemImage: "play.circle.fill")

            Toggle(isOn: $playLocally) {
                Text(L10n.text("toggle.play.locally"))
                    .font(.system(.body, design: .rounded))
            }
            .tint(GlassTheme.accent)

            Toggle(isOn: $playlist.autoAdvance) {
                Text(L10n.text("toggle.auto.next"))
                    .font(.system(.body, design: .rounded))
            }
            .tint(GlassTheme.accent)
            .disabled(session.isStreamingSystemAudio)

            HStack(spacing: 10) {
                Button(L10n.text("action.choose.audio")) { isFileImporterPresented = true }
                    .buttonStyle(GlassSecondaryButtonStyle())
                    .disabled(session.isStreamingSystemAudio)

                Button(L10n.text("action.choose.folder")) { isFolderImporterPresented = true }
                    .buttonStyle(GlassSecondaryButtonStyle())
                    .disabled(session.isStreamingSystemAudio)

                Button(L10n.text("action.test.tone")) {
                    playlist.appendDemoTone()
                    playlistError = nil
                }
                .buttonStyle(GlassSecondaryButtonStyle())
                .disabled(session.isStreamingSystemAudio)
            }

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

            if let current = playlist.currentItem {
                Text(L10n.format("playlist.now.playing", current.title))
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .foregroundStyle(GlassTheme.accent)
                    .lineLimit(2)
            }

            if let playlistError {
                Text(playlistError)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.red.opacity(0.85))
            }

            HStack(spacing: 12) {
                Button {
                    playPrevious()
                } label: {
                    Image(systemName: "backward.fill")
                }
                .buttonStyle(GlassSecondaryButtonStyle())
                .disabled(!canPlay || !playlist.hasPrevious || session.isStreamingSystemAudio)

                Button(L10n.text("action.sync.play")) {
                    playCurrent()
                }
                .buttonStyle(GlassPrimaryButtonStyle(enabled: canPlay))
                .disabled(!canPlay)

                Button {
                    playNext()
                } label: {
                    Image(systemName: "forward.fill")
                }
                .buttonStyle(GlassSecondaryButtonStyle())
                .disabled(!canPlay || !playlist.hasNext || session.isStreamingSystemAudio)

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

    private var playlistSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle(L10n.text("section.playlist"), systemImage: "list.bullet")
                Spacer()
                Text("\(playlist.items.count)")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if let message = playlist.loadMessage {
                Text(message)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if playlist.items.isEmpty {
                emptyHint(L10n.text("hint.playlist.empty"))
                    .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(playlist.items.enumerated()), id: \.element.id) { index, item in
                            playlistRow(item, index: index)
                        }
                    }
                }
                .frame(minHeight: 180, maxHeight: 280)
            }

            HStack {
                Button(L10n.text("action.playlist.clear")) {
                    playlist.clear()
                    playlistError = nil
                }
                .buttonStyle(GlassSecondaryButtonStyle())
                .disabled(playlist.items.isEmpty || session.isStreamingSystemAudio)
                Spacer()
            }
        }
    }

    private func playlistRow(_ item: PlaylistItem, index: Int) -> some View {
        let isCurrent = playlist.currentIndex == index
        return HStack(spacing: 8) {
            Button {
                playlist.select(index: index)
                if !session.connectedSpeakers.isEmpty, !session.isStreamingSystemAudio {
                    playCurrent()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isCurrent && session.phase == .playing ? "speaker.wave.2.fill" : "music.note")
                        .font(.caption)
                        .foregroundStyle(isCurrent ? GlassTheme.accent : .secondary)
                        .frame(width: 16)
                    Text(item.title)
                        .font(.system(.subheadline, design: .rounded).weight(isCurrent ? .semibold : .regular))
                        .foregroundStyle(isCurrent ? .primary : .secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                playlist.remove(id: item.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isCurrent ? GlassTheme.accent.opacity(0.14) : Color.clear)
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

    private func playCurrent() {
        do {
            let track = try playlist.loadTrack()
            playlistError = nil
            session.play(track: track, alsoPlayLocally: playLocally)
        } catch {
            playlistError = L10n.text("error.playlist.load")
        }
    }

    private func playNext() {
        guard playlist.moveToNext() != nil else { return }
        playCurrent()
    }

    private func playPrevious() {
        guard playlist.moveToPrevious() != nil else { return }
        playCurrent()
    }

    private func playNextIfPossible() {
        guard playlist.autoAdvance, playlist.hasNext else { return }
        playNext()
    }

    private func handleAudioImport(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            var accessed: [URL] = []
            for url in urls {
                if url.startAccessingSecurityScopedResource() {
                    accessed.append(url)
                }
            }
            defer { accessed.forEach { $0.stopAccessingSecurityScopedResource() } }
            playlist.importAudioURLs(urls)
            playlistError = nil
        } catch {
            playlistError = L10n.text("error.playlist.import")
        }
    }

    private func handleFolderImport(_ result: Result<[URL], Error>) {
        do {
            guard let folder = try result.get().first else { return }
            playlist.importFolder(folder)
            playlistError = nil
        } catch {
            playlistError = L10n.text("error.playlist.import")
        }
    }
}
