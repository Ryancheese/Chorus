import SwiftUI

public struct LanguageMenu: View {
    @ObservedObject private var settings: LanguageSettings

    public init(settings: LanguageSettings) {
        self.settings = settings
    }

    public var body: some View {
        Menu {
            ForEach(LanguageChoice.allCases) { language in
                Button {
                    settings.selection = language
                } label: {
                    if settings.selection == language {
                        Label(language.displayName, systemImage: "checkmark")
                    } else {
                        Text(language.displayName)
                    }
                }
            }
        } label: {
            Label(L10n.text("action.language"), systemImage: "globe")
        }
    }
}
