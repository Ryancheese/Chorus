import SwiftUI
import ChorusCore

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
    @StateObject private var languageSettings = LanguageSettings()
    @StateObject private var appearanceSettings = AppearanceSettings()
    @StateObject private var audioAtmosphere = AudioAtmosphereSettings()
    @State private var appeared = false
    @State private var isHelpPresented = false
    @State private var isOnboardingPresented = false
    @State private var liveActivityManager = SpeakerLiveActivityManager()

    private var isBroadcasting: Bool {
        session.phase != .idle
    }

    private var isPlaying: Bool {
        session.phase == .playing
    }

    var body: some View {
        let _ = languageSettings.selection
        ZStack {
            LiquidGlassBackground(
                intensity: 1.15,
                audioLevel: session.audioLevel,
                reactsToAudio: audioAtmosphere.musicPulseEnabled
            )

            GeometryReader { proxy in
                ScrollView {
                    responsiveContent(in: proxy.size)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: proxy.size.height)
                }
                .chorusScrollBounceBasedOnSize()
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 18)
        }
        .onAppear {
            withAnimation(.spring(response: 0.75, dampingFraction: 0.84)) {
                appeared = true
            }
            liveActivityManager.update(
                phase: session.phase,
                sessionTitle: session.sessionTitle,
                hostName: session.hostName,
                roundTripMs: session.roundTripMs
            )
            if !SpeakerOnboardingStore.isCompleted {
                isOnboardingPresented = true
            }
        }
        .chorusOnChange(of: session.phase) { phase in
            liveActivityManager.update(
                phase: phase,
                sessionTitle: session.sessionTitle,
                hostName: session.hostName,
                roundTripMs: session.roundTripMs
            )
        }
        .chorusOnChange(of: session.sessionTitle) { title in
            liveActivityManager.update(
                phase: session.phase,
                sessionTitle: title,
                hostName: session.hostName,
                roundTripMs: session.roundTripMs
            )
        }
        .chorusOnChange(of: session.hostName) { host in
            liveActivityManager.update(
                phase: session.phase,
                sessionTitle: session.sessionTitle,
                hostName: host,
                roundTripMs: session.roundTripMs
            )
        }
        .chorusOnChange(of: session.roundTripMs) { rtt in
            liveActivityManager.update(
                phase: session.phase,
                sessionTitle: session.sessionTitle,
                hostName: session.hostName,
                roundTripMs: rtt
            )
        }
        .sheet(isPresented: $isHelpPresented) {
            ChorusHelpView(role: .speaker)
        }
        .sheet(isPresented: $isOnboardingPresented) {
            SpeakerOnboardingView {
                SpeakerOnboardingStore.markCompleted()
                isOnboardingPresented = false
            }
        }
        .alert(
            L10n.text("alert.sync.exited.title"),
            isPresented: Binding(
                get: { session.audioDisruptionMessage != nil },
                set: { if !$0 { session.clearAudioDisruptionMessage() } }
            )
        ) {
            Button(L10n.text("action.close"), role: .cancel) {
                session.clearAudioDisruptionMessage()
            }
        } message: {
            Text(session.audioDisruptionMessage ?? "")
        }
        .chorusAppearance(appearanceSettings)
    }

    @ViewBuilder
    private func responsiveContent(in size: CGSize) -> some View {
        if size.width >= 760 {
            wideLayout
        } else {
            compactLayout
        }
    }

    private var compactLayout: some View {
        VStack(spacing: 0) {
            utilityBar
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 22)
                .padding(.top, 16)

            Spacer(minLength: 20)

            brandBlock(isWide: false)
                .padding(.bottom, 28)

            glassStatus
                .padding(.horizontal, 22)

            Spacer(minLength: 28)

            primaryAction
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
        }
    }

    private var wideLayout: some View {
        VStack(spacing: 0) {
            utilityBar
                .frame(maxWidth: .infinity, alignment: .trailing)

            Spacer(minLength: 24)

            HStack(spacing: 48) {
                brandBlock(isWide: true)
                    .frame(maxWidth: .infinity)

                VStack(spacing: 24) {
                    glassStatus
                    primaryAction
                }
                .frame(maxWidth: 520)
            }

            Spacer(minLength: 32)
        }
        .frame(maxWidth: 1080)
        .padding(.horizontal, 48)
        .padding(.vertical, 28)
    }

    private func brandBlock(isWide: Bool) -> some View {
        VStack(spacing: 18) {
            PulsingOrb(
                isActive: isBroadcasting,
                symbol: isPlaying ? "speaker.wave.3.fill" : "hifispeaker.fill"
            )

            VStack(spacing: 8) {
                Text("Chorus")
                    .font(.system(size: isWide ? 56 : 42, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(L10n.text("app.speaker"))
                    .font(.system(isWide ? .title2 : .title3, design: .rounded).weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var glassStatus: some View {
        GlassPanel(cornerRadius: 28, padding: 24) {
            VStack(spacing: 12) {
                Text(session.phase.displayName)
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .foregroundStyle(.primary)
                    .chorusContentTransitionOpacity()

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
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
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
                        .padding(.top, 2)
                }

                if let audioTip = session.audioOutputWarning {
                    Text(audioTip)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: session.phase.displayName)
    }

    private func metricChip(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(.primary)
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
        // Narrow phones can't fit four labeled chips; fall back to icons.
        ChorusHorizontalFitBar {
            utilityControls(iconOnly: false, compact: false, spacing: 10)
        } fallback: {
            utilityControls(iconOnly: true, compact: true, spacing: 8)
        }
    }

    private func utilityControls(iconOnly: Bool, compact: Bool, spacing: CGFloat) -> some View {
        let stack = HStack(spacing: spacing) {
            LanguageMenu(settings: languageSettings)
            AppearanceMenu(settings: appearanceSettings)
            AudioAtmosphereMenu(settings: audioAtmosphere)
            Button {
                isHelpPresented = true
            } label: {
                if iconOnly {
                    Image(systemName: "questionmark.circle")
                } else {
                    Label(L10n.text("action.help"), systemImage: "questionmark.circle")
                }
            }
            .accessibilityLabel(L10n.text("action.help"))
        }
        .buttonStyle(GlassSecondaryButtonStyle(compact: compact))
        .fixedSize(horizontal: true, vertical: false)

        return Group {
            if iconOnly {
                stack.labelStyle(.iconOnly)
            } else {
                stack.labelStyle(.titleAndIcon)
            }
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
