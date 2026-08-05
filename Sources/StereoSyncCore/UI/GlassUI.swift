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
    @State private var phase: CGFloat = 0

    public init(intensity: Double = 1) {
        self.intensity = intensity
    }

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.90, green: 0.94, blue: 0.98),
                    Color(red: 0.86, green: 0.90, blue: 0.95),
                    Color(red: 0.92, green: 0.93, blue: 0.96)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(GlassTheme.accentSoft.opacity(0.45 * intensity))
                .frame(width: 340, height: 340)
                .blur(radius: 55)
                .offset(x: -90 + 18 * sin(phase), y: -160 + 12 * cos(phase * 0.8))

            Circle()
                .fill(GlassTheme.mint.opacity(0.38 * intensity))
                .frame(width: 280, height: 280)
                .blur(radius: 50)
                .offset(x: 120 + 14 * cos(phase * 1.1), y: 40 + 16 * sin(phase * 0.7))

            Circle()
                .fill(Color.white.opacity(0.55 * intensity))
                .frame(width: 220, height: 220)
                .blur(radius: 40)
                .offset(x: 20, y: 180 + 10 * sin(phase * 1.3))
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                phase = .pi * 2
            }
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
            .foregroundStyle(GlassTheme.brand.opacity(0.85))
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

    @State private var pulse = false

    public init(isActive: Bool, symbol: String = "waveform") {
        self.isActive = isActive
        self.symbol = symbol
    }

    public var body: some View {
        ZStack {
            Circle()
                .fill(GlassTheme.accentSoft.opacity(isActive ? 0.28 : 0.12))
                .frame(width: 148, height: 148)
                .scaleEffect(pulse && isActive ? 1.12 : 1)
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
