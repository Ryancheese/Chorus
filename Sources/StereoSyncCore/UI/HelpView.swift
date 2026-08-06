import SwiftUI

public enum HelpRole {
    case host
    case speaker
}

public struct StereoSyncHelpView: View {
    private let role: HelpRole
    @Environment(\.dismiss) private var dismiss

    public init(role: HelpRole) {
        self.role = role
    }

    public var body: some View {
        NavigationStack {
            List {
                if role == .host {
                    helpSection("help.host.setup.title", "help.host.setup.body")
                    helpSection("help.host.playback.title", "help.host.playback.body")
                    helpSection("help.host.system.title", "help.host.system.body")
                } else {
                    helpSection("help.speaker.title", "help.speaker.body")
                }
                helpSection("help.troubleshooting.title", "help.troubleshooting.body")
            }
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

    private func helpSection(_ title: String, _ body: String) -> some View {
        Section(L10n.text(title)) {
            Text(L10n.text(body))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 4)
        }
    }
}
