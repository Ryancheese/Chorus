import SwiftUI
import StereoSyncCore
import UniformTypeIdentifiers

@main
struct HostApp: App {
    var body: some Scene {
        WindowGroup {
            HostRootView()
                .frame(minWidth: 560, minHeight: 480)
        }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            statusCard
            discoveredList
            connectedList
            controls
            Spacer(minLength: 0)
        }
        .padding(28)
        .background(atmosphere)
        .onAppear { browser.start() }
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
        VStack(alignment: .leading, spacing: 6) {
            Text("StereoSync")
                .font(.system(size: 34, weight: .bold, design: .rounded))
            Text("Mac 主机 · 局域网同步扬声器")
                .foregroundStyle(.secondary)
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(session.phase.rawValue, systemImage: "dot.radiowaves.left.and.right")
                .font(.headline)
            Text(session.statusText)
                .foregroundStyle(.secondary)
            if let rtt = session.bestRTT {
                Text(String(format: "往返延迟 ≈ %.0f ms", rtt * 1000))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let error = session.lastError {
                Text(error).foregroundStyle(.red).font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var discoveredList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("发现的扬声器").font(.headline)
            if browser.peers.isEmpty {
                Text("请在 iPhone / iPad 打开 Speaker 并点「开始广播」")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(browser.peers) { peer in
                    HStack {
                        Image(systemName: "iphone.gen3")
                        Text(peer.name)
                        Spacer()
                        if connectedEndpoints.contains(peer.endpointDebug) {
                            Text("已连接").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Button("连接") {
                                session.connect(to: peer)
                                connectedEndpoints.insert(peer.endpointDebug)
                            }
                        }
                    }
                }
            }
        }
    }

    private var connectedList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("会话设备").font(.headline)
            if session.connectedSpeakers.isEmpty {
                Text("尚未完成握手").foregroundStyle(.secondary)
            } else {
                ForEach(session.connectedSpeakers) { speaker in
                    HStack {
                        Image(systemName: "hifispeaker.fill")
                        Text(speaker.name)
                        Spacer()
                        Text("就绪").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("本机同时播放", isOn: $playLocally)
            HStack {
                Button("选择音频文件") { isImporterPresented = true }
                Button("加载测试音调") {
                    let track = DemoTone.makeTrack()
                    loadedTrack = track
                    selectedFileName = track.title
                }
                if let name = selectedFileName {
                    Text(name).lineLimit(1).foregroundStyle(.secondary)
                }
            }
            HStack {
                Button("同步播放") {
                    guard let track = loadedTrack else { return }
                    session.play(track: track, alsoPlayLocally: playLocally)
                }
                .buttonStyle(.borderedProminent)
                .disabled(loadedTrack == nil || session.connectedSpeakers.isEmpty)

                Button("停止") { session.stop() }
                    .disabled(session.phase != .playing)
            }
        }
    }

    private var atmosphere: some View {
        LinearGradient(
            colors: [
                Color(red: 0.93, green: 0.95, blue: 0.98),
                Color(red: 0.86, green: 0.90, blue: 0.94)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let track = try AudioFileLoader.load(url: url)
            loadedTrack = track
            selectedFileName = track.title
        } catch {
            selectedFileName = nil
            loadedTrack = nil
        }
    }
}
