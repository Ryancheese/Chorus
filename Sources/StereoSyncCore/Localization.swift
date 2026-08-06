import Foundation
import Combine

/// Centralizes all user-facing copy in StereoSyncCore's localized resource bundle.
public enum L10n {
    public static let supportedLanguageCodes = ["en", "zh-Hans", "ja", "ko"]
    public static let defaultLanguageCode = "zh-Hans"
    static let languagePreferenceKey = "stereosync.language"

    public static func text(_ key: String) -> String {
        text(key, languageCode: preferredLanguageCode)
    }

    public static func text(_ key: String, languageCode: String) -> String {
        guard let path = Bundle.module.path(forResource: languageCode, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else {
            return text(key)
        }
        return bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }

    public static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: .current, arguments: arguments)
    }

    private static var preferredLanguageCode: String {
        if let override = UserDefaults.standard.string(forKey: languagePreferenceKey),
           override != LanguageChoice.system.rawValue {
            return override
        }
        let identifier = Locale.preferredLanguages.first?.lowercased() ?? ""
        if identifier.hasPrefix("zh") {
            return "zh-Hans"
        }
        if identifier.hasPrefix("ja") {
            return "ja"
        }
        if identifier.hasPrefix("ko") {
            return "ko"
        }
        if identifier.hasPrefix("en") {
            return "en"
        }
        return defaultLanguageCode
    }
}

public enum LanguageChoice: String, CaseIterable, Identifiable {
    case system
    case chinese = "zh-Hans"
    case english = "en"
    case japanese = "ja"
    case korean = "ko"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: "跟随系统"
        case .chinese: "简体中文"
        case .english: "English"
        case .japanese: "日本語"
        case .korean: "한국어"
        }
    }
}

@MainActor
public final class LanguageSettings: ObservableObject {
    @Published public var selection: LanguageChoice {
        didSet {
            UserDefaults.standard.set(selection.rawValue, forKey: L10n.languagePreferenceKey)
        }
    }

    public init() {
        selection = LanguageChoice(
            rawValue: UserDefaults.standard.string(forKey: L10n.languagePreferenceKey) ?? ""
        ) ?? .system
    }
}
