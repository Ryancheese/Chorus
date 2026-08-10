import SwiftUI

public enum HelpRole {
    case host
    case speaker
}

public struct ChorusHelpView: View {
    private let role: HelpRole
    @Environment(\.dismiss) private var dismiss

    public init(role: HelpRole) {
        self.role = role
    }

    public var body: some View {
        ChorusNavigationContainer {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if role == .host {
                        helpBlock("help.host.setup.title", "help.host.setup.body")
                        helpBlock("help.host.playback.title", "help.host.playback.body")
                        helpBlock("help.host.system.title", "help.host.system.body")
                    } else {
                        helpBlock("help.speaker.title", "help.speaker.body")
                        #if os(macOS)
                        helpBlock("help.speaker.mac.title", "help.speaker.mac.body")
                        #endif
                    }
                    helpBlock("help.troubleshooting.title", "help.troubleshooting.body")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            #if os(macOS)
            .frame(minWidth: 440, idealWidth: 520, minHeight: 420, idealHeight: 540)
            #endif
            .navigationTitle(L10n.text("help.title"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("action.close")) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func helpBlock(_ titleKey: String, _ bodyKey: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text(titleKey))
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .foregroundStyle(.primary)
            Text(L10n.text(bodyKey))
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.thinMaterial)
        }
    }
}
