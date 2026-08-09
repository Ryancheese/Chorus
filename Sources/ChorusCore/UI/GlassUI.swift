import SwiftUI

/// Shared liquid-glass visual language for Host + Speaker.
public enum GlassTheme {
    public static let brand = Color(red: 0.12, green: 0.14, blue: 0.18)
    public static let accent = Color(red: 0.18, green: 0.52, blue: 0.86)
    public static let accentSoft = Color(red: 0.35, green: 0.72, blue: 0.92)
    public static let mint = Color(red: 0.45, green: 0.82, blue: 0.78)
    public static let mist = Color(red: 0.94, green: 0.96, blue: 0.98)
}

public struct LiquidGlassBackground: View {
    public var intensity: Double
    /// 0–1 smoothed peak; drives blob size / travel like Apple Music ambient.
    public var audioLevel: Double
    @State private var phase: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme

    public init(intensity: Double = 1, audioLevel: Double = 0) {
        self.intensity = intensity
        self.audioLevel = min(1, max(0, audioLevel))
    }

    public var body: some View {
        let level = CGFloat(audioLevel)
        let amp = 1 + level * 2.2
        let breath = 1 + level * 0.42
        ZStack {
            LinearGradient(
                colors: backgroundColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(GlassTheme.accentSoft.opacity((0.45 + 0.4 * audioLevel) * intensity))
                .frame(width: 340 * breath, height: 340 * breath)
                .blur(radius: 55)
                .offset(x: -90 + 18 * amp * sin(phase), y: -160 + 12 * amp * cos(phase * 0.8))

            Circle()
                .fill(GlassTheme.mint.opacity((0.38 + 0.38 * audioLevel) * intensity))
                .frame(width: 280 * breath, height: 280 * breath)
                .blur(radius: 50)
                .offset(x: 120 + 14 * amp * cos(phase * 1.1), y: 40 + 16 * amp * sin(phase * 0.7))

            Circle()
                .fill(
                    (colorScheme == .dark ? Color(red: 0.18, green: 0.23, blue: 0.32) : .white)
                        .opacity((0.55 + 0.25 * audioLevel) * intensity)
                )
                .frame(width: 220 * (1 + level * 0.28), height: 220 * (1 + level * 0.28))
                .blur(radius: 40)
                .offset(x: 20 + 8 * level * cos(phase * 0.9), y: 180 + 10 * amp * sin(phase * 1.3))
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.55), value: colorScheme)
        .animation(.easeOut(duration: 0.12), value: audioLevel)
        .onAppear {
            withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                phase = .pi * 2
            }
        }
    }

    private var backgroundColors: [Color] {
        if colorScheme == .dark {
            [
                Color(red: 0.04, green: 0.06, blue: 0.10),
                Color(red: 0.07, green: 0.11, blue: 0.18),
                Color(red: 0.05, green: 0.08, blue: 0.13)
            ]
        } else {
            [
                Color(red: 0.90, green: 0.94, blue: 0.98),
                Color(red: 0.86, green: 0.90, blue: 0.95),
                Color(red: 0.92, green: 0.93, blue: 0.96)
            ]
        }
    }
}

public struct GlassPanel<Content: View>: View {
    private let content: Content
    private let cornerRadius: CGFloat
    private let padding: CGFloat

    public init(
        cornerRadius: CGFloat = 24,
        padding: CGFloat = 20,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.75),
                                        Color.white.opacity(0.18),
                                        Color.white.opacity(0.45)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                    .shadow(color: Color.black.opacity(0.08), radius: 24, y: 12)
            }
    }
}

public struct GlassPrimaryButtonStyle: ButtonStyle {
    public var enabled: Bool

    public init(enabled: Bool = true) {
        self.enabled = enabled
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded).weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background {
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: enabled
                                ? [GlassTheme.accent, GlassTheme.accentSoft]
                                : [Color.gray.opacity(0.45), Color.gray.opacity(0.35)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                    }
                    .shadow(color: GlassTheme.accent.opacity(enabled ? 0.35 : 0), radius: 16, y: 8)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

public struct GlassSecondaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background {
                Capsule(style: .continuous)
                    .fill(.thinMaterial)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(0.55), lineWidth: 1)
                    }
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

public struct PulsingOrb: View {
    public var isActive: Bool
    public var symbol: String
    public var audioLevel: Double

    @State private var pulse = false

    public init(isActive: Bool, symbol: String = "waveform", audioLevel: Double = 0) {
        self.isActive = isActive
        self.symbol = symbol
        self.audioLevel = min(1, max(0, audioLevel))
    }

    public var body: some View {
        let beat = 1 + CGFloat(audioLevel) * 0.22
        ZStack {
            Circle()
                .fill(GlassTheme.accentSoft.opacity((isActive ? 0.28 : 0.12) + 0.22 * audioLevel))
                .frame(width: 148, height: 148)
                .scaleEffect((pulse && isActive ? 1.12 : 1) * beat)
                .blur(radius: 2)

            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 112, height: 112)
                .overlay {
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.8), Color.white.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.2
                        )
                }
                .shadow(color: Color.black.opacity(0.1), radius: 20, y: 10)

            Image(systemName: symbol)
                .font(.system(size: 36, weight: .medium, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [GlassTheme.accent, GlassTheme.mint],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .symbolEffect(.variableColor.iterative, isActive: isActive)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}
