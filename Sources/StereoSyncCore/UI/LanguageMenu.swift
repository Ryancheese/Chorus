import SwiftUI

public struct LanguageMenu: View {
    @ObservedObject private var settings: LanguageSettings

    public init(settings: LanguageSettings) {
        self.settings = settings
    }

    public var body: some View {
        Menu {
            Picker(L10n.text("action.language"), selection: $settings.selection) {
                ForEach(LanguageChoice.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
        } label: {
            Label(L10n.text("action.language"), systemImage: "globe")
        }
    }
}
