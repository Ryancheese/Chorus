import SwiftUI
import StereoSyncCore

@main
struct SpeakerApp: App {
    var body: some Scene {
        WindowGroup {
            SpeakerRootView()
        }
    }
}

struct SpeakerRootView: View {
    @StateObject private var session = SpeakerSessionController()
    @State private var appeared = false

    private var isBroadcasting: Bool {
        session.phase != .idle
    }

    private var isPlaying: Bool {
        session.phase == .playing
    }

    var body: some View {
        ZStack {
            LiquidGlassBackground(intensity: 1.15)

            VStack(spacing: 0) {
                Spacer(minLength: 24)

                brandBlock
                    .padding(.bottom, 28)

                glassStatus
                    .padding(.horizontal, 22)

                Spacer()

                primaryAction
                    .padding(.horizontal, 28)
                    .padding(.bottom, 36)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 18)
        }
        .preferredColorScheme(.light)
        .onAppear {
            withAnimation(.spring(response: 0.75, dampingFraction: 0.84)) {
                appeared = true
            }
        }
        .onDisappear { session.stopAll() }
    }

    private var brandBlock: some View {
        VStack(spacing: 18) {
            PulsingOrb(
                isActive: isBroadcasting,
                symbol: isPlaying ? "speaker.wave.3.fill" : "hifispeaker.fill"
            )

            VStack(spacing: 8) {
                Text("StereoSync")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(GlassTheme.brand)

                Text("扬声器")
                    .font(.system(.title3, design: .rounded).weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var glassStatus: some View {
        GlassPanel(cornerRadius: 28, padding: 24) {
            VStack(spacing: 12) {
                Text(session.phase.rawValue)
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .foregroundStyle(GlassTheme.brand)
                    .contentTransition(.opacity)

                Text(session.statusText)
                    .font(.system(.body, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 280)

                if isBroadcasting && session.hostName == nil {
                    VStack(spacing: 6) {
                        if let address = session.connectionAddress {
                            Text("本机地址")
                                .font(.system(.caption2, design: .rounded).weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(address)
                                .font(.system(.title3, design: .monospaced).weight(.semibold))
                                .foregroundStyle(GlassTheme.accent)
                                .textSelection(.enabled)
                        }
                        Text("把上面的 IP 填进 Mac「手动连接」")
                            .font(.system(.caption, design: .rounded))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }

                if session.hostName != nil || session.clockOffsetMs != nil {
                    HStack(spacing: 18) {
                        if let host = session.hostName {
                            metricChip(title: "主机", value: host)
                        }
                        if let ms = session.clockOffsetMs {
                            metricChip(title: "偏移", value: String(format: "%.0f ms", ms))
                        }
                    }
                    .padding(.top, 6)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }

                if let error = session.lastError {
                    Text(error)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.red.opacity(0.85))
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: session.phase.rawValue)
    }

    private func metricChip(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(GlassTheme.brand)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            Capsule(style: .continuous)
                .fill(.thinMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
                }
        }
    }

    private var primaryAction: some View {
        Button(action: toggle) {
            Text(isBroadcasting ? "停止" : "开始广播")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(GlassPrimaryButtonStyle(enabled: true))
        .shadow(color: GlassTheme.accent.opacity(0.22), radius: 24, y: 10)
    }

    private func toggle() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
            if session.phase == .idle {
                session.startAdvertising()
            } else {
                session.stopAll()
            }
        }
    }
}
