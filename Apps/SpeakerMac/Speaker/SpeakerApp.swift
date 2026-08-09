import SwiftUI
import ChorusCore

@main
struct SpeakerMacApp: App {
    var body: some Scene {
        WindowGroup {
            SpeakerMacRootView()
                .frame(minWidth: 420, minHeight: 560)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 480, height: 640)
    }
}

struct SpeakerMacRootView: View {
    @StateObject private var session = SpeakerSessionController()
    @StateObject private var languageSettings = LanguageSettings()
    @StateObject private var appearanceSettings = AppearanceSettings()
    @State private var appeared = false
    @State private var isHelpPresented = false

    private var isBroadcasting: Bool {
        session.phase != .idle
    }

    private var isPlaying: Bool {
        session.phase == .playing
    }

    var body: some View {
        let _ = languageSettings.selection
        ZStack {
            LiquidGlassBackground(intensity: 1.15)

            VStack(spacing: 0) {
                utilityBar
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 22)
                    .padding(.top, 16)

                Spacer(minLength: 20)

                brandBlock
                    .padding(.bottom, 28)

                glassStatus
                    .padding(.horizontal, 22)

                Text(L10n.text("help.speaker.mac.body"))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .padding(.top, 16)

                Spacer(minLength: 28)

                primaryAction
                    .padding(.horizontal, 28)
                    .padding(.bottom, 28)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 18)
        }
        .onAppear {
            withAnimation(.spring(response: 0.75, dampingFraction: 0.84)) {
                appeared = true
            }
        }
        .sheet(isPresented: $isHelpPresented) {
            ChorusHelpView(role: .speaker)
        }
        .chorusAppearance(appearanceSettings)
    }

    private var brandBlock: some View {
        VStack(spacing: 18) {
            PulsingOrb(
                isActive: isBroadcasting,
                symbol: isPlaying ? "speaker.wave.3.fill" : "hifispeaker.fill"
            )

            VStack(spacing: 8) {
                Text("Chorus")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(L10n.text("app.speaker"))
                    .font(.system(.title3, design: .rounded).weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var glassStatus: some View {
        GlassPanel(cornerRadius: 28, padding: 24) {
            VStack(spacing: 12) {
                Text(session.phase.displayName)
                    .font(.system(.title2, design: .rounded).weight(.semibold))

                Text(session.statusText)
                    .font(.system(.body, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 280)

                if isBroadcasting && session.hostName == nil {
                    VStack(spacing: 6) {
                        if let address = session.connectionAddress {
                            Text(L10n.text("label.address"))
                                .font(.system(.caption2, design: .rounded).weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(address)
                                .font(.system(.title3, design: .monospaced).weight(.semibold))
                                .foregroundStyle(GlassTheme.accent)
                                .textSelection(.enabled)
                        }
                        Text(L10n.text("hint.manual.ip"))
                            .font(.system(.caption, design: .rounded))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }

                if session.hostName != nil || session.clockOffsetMs != nil {
                    HStack(spacing: 18) {
                        if let host = session.hostName {
                            metricChip(title: L10n.text("label.host"), value: host)
                        }
                        if session.clockOffsetMs != nil {
                            metricChip(title: L10n.text("label.clock"), value: L10n.text("label.calibrated"))
                        }
                    }
                    .padding(.top, 6)
                }

                if let error = session.lastError, session.phase != .playing {
                    Text(error)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.red.opacity(0.85))
                        .multilineTextAlignment(.center)
                }

                if let warning = session.networkWarning {
                    Text(warning)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func metricChip(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
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
            Text(isBroadcasting ? L10n.text("action.stop") : L10n.text("action.start.broadcasting"))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(GlassPrimaryButtonStyle(enabled: true))
        .shadow(color: GlassTheme.accent.opacity(0.22), radius: 24, y: 10)
    }

    private var utilityBar: some View {
        HStack(spacing: 12) {
            LanguageMenu(settings: languageSettings)
                .buttonStyle(GlassSecondaryButtonStyle())
            AppearanceMenu(settings: appearanceSettings)
                .buttonStyle(GlassSecondaryButtonStyle())
            Button {
                isHelpPresented = true
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .buttonStyle(GlassSecondaryButtonStyle())
            .accessibilityLabel(L10n.text("action.help"))
        }
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
