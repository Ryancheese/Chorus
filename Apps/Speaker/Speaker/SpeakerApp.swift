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

    var body: some View {
        ZStack {
            atmosphere
            VStack(spacing: 28) {
                VStack(spacing: 8) {
                    Text("StereoSync")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    Text("扬声器")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 48)

                statusBlock

                Spacer()

                Button(action: toggle) {
                    Text(session.isAdvertising || session.phase != .idle ? "停止" : "开始广播")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 28)
                .padding(.bottom, 40)
            }
        }
        .onDisappear { session.stopAll() }
    }

    private var statusBlock: some View {
        VStack(spacing: 10) {
            Text(session.phase.rawValue)
                .font(.title2.weight(.semibold))
            Text(session.statusText)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
            if let host = session.hostName {
                Text("主机：\(host)")
                    .font(.subheadline)
            }
            if let ms = session.clockOffsetMs {
                Text(String(format: "时钟偏移 ≈ %.0f ms", ms))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let error = session.lastError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 24)
    }

    private var atmosphere: some View {
        LinearGradient(
            colors: [
                Color(red: 0.12, green: 0.16, blue: 0.22),
                Color(red: 0.18, green: 0.28, blue: 0.34)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .overlay(
            Circle()
                .fill(Color.cyan.opacity(0.18))
                .frame(width: 280, height: 280)
                .blur(radius: 40)
                .offset(y: -120)
        )
        .preferredColorScheme(.dark)
    }

    private func toggle() {
        if session.phase == .idle {
            session.startAdvertising()
        } else {
            session.stopAll()
        }
    }
}
