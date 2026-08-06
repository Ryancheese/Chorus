import Combine
import Foundation
import SwiftUI

public enum AppearanceChoice: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    public var displayName: String {
        switch self {
        case .system: L10n.text("appearance.system")
        case .light: L10n.text("appearance.light")
        case .dark: L10n.text("appearance.dark")
        }
    }

    public var systemImage: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon.fill"
        }
    }
}

@MainActor
public final class AppearanceSettings: ObservableObject {
    static let preferenceKey = "chorus.appearance"

    @Published public var selection: AppearanceChoice {
        didSet {
            UserDefaults.standard.set(selection.rawValue, forKey: Self.preferenceKey)
        }
    }

    public init() {
        selection = AppearanceChoice(
            rawValue: UserDefaults.standard.string(forKey: Self.preferenceKey) ?? ""
        ) ?? .system
    }
}

public struct AppearanceMenu: View {
    @ObservedObject private var settings: AppearanceSettings

    public init(settings: AppearanceSettings) {
        self.settings = settings
    }

    public var body: some View {
        Menu {
            ForEach(AppearanceChoice.allCases) { choice in
                Button {
                    guard settings.selection != choice else { return }
                    settings.selection = choice
                } label: {
                    if settings.selection == choice {
                        Label(choice.displayName, systemImage: "checkmark")
                    } else {
                        Text(choice.displayName)
                    }
                }
            }
        } label: {
            Label(L10n.text("action.appearance"), systemImage: settings.selection.systemImage)
        }
    }
}

/// Soft crossfade when switching light / dark / system, to avoid harsh contrast flashes.
struct ChorusAppearanceModifier: ViewModifier {
    @ObservedObject var settings: AppearanceSettings
    @State private var appliedScheme: ColorScheme?
    @State private var veilOpacity: Double = 0
    @State private var transitionID = UUID()

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(appliedScheme)
            .overlay {
                // Mid-tone veil bridges light ↔ dark so the jump is gentler on eyes.
                Rectangle()
                    .fill(Color(red: 0.40, green: 0.44, blue: 0.50))
                    .opacity(veilOpacity)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            .onAppear {
                appliedScheme = settings.selection.preferredColorScheme
            }
            .onChange(of: settings.selection) { _, newValue in
                transition(to: newValue.preferredColorScheme)
            }
    }

    private func transition(to scheme: ColorScheme?) {
        let id = UUID()
        transitionID = id
        Task { @MainActor in
            withAnimation(.easeInOut(duration: 0.22)) {
                veilOpacity = 0.32
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard transitionID == id else { return }
            withAnimation(.easeInOut(duration: 0.55)) {
                appliedScheme = scheme
                veilOpacity = 0
            }
        }
    }
}

public extension View {
    func chorusAppearance(_ settings: AppearanceSettings) -> some View {
        modifier(ChorusAppearanceModifier(settings: settings))
    }
}
