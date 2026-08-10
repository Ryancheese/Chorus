import SwiftUI

/// First-launch walkthrough for Chorus Host.
public struct HostOnboardingView: View {
    public var onFinished: () -> Void

    public init(onFinished: @escaping () -> Void) {
        self.onFinished = onFinished
    }

    public var body: some View {
        ChorusNavigationContainer {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(L10n.text("onboarding.host.welcome"))
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .foregroundStyle(.primary)

                    Text(L10n.text("onboarding.host.subtitle"))
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    step(
                        number: 1,
                        title: L10n.text("onboarding.host.step1.title"),
                        body: L10n.text("onboarding.host.step1.body")
                    )
                    step(
                        number: 2,
                        title: L10n.text("onboarding.host.step2.title"),
                        body: L10n.text("onboarding.host.step2.body")
                    )
                    step(
                        number: 3,
                        title: L10n.text("onboarding.host.step3.title"),
                        body: L10n.text("onboarding.host.step3.body")
                    )
                    step(
                        number: 4,
                        title: L10n.text("onboarding.host.step4.title"),
                        body: L10n.text("onboarding.host.step4.body")
                    )

                    Button(L10n.text("onboarding.host.start")) {
                        onFinished()
                    }
                    .buttonStyle(GlassPrimaryButtonStyle())
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            #if os(macOS)
            .frame(minWidth: 480, idealWidth: 540, minHeight: 520, idealHeight: 620)
            #endif
            .navigationTitle(L10n.text("onboarding.host.title"))
        }
    }

    private func step(number: Int, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(GlassTheme.accent))

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.primary)
                Text(body)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.thinMaterial)
        }
    }
}

public enum HostOnboardingStore {
    public static let completedKey = "chorus.host.onboarding.completed"

    public static var isCompleted: Bool {
        UserDefaults.standard.bool(forKey: completedKey)
    }

    public static func markCompleted() {
        UserDefaults.standard.set(true, forKey: completedKey)
    }
}
