/// A language Zack can dictate in. One language per user; it selects the language pack.
public enum DictationLanguage: String, CaseIterable, Sendable, Codable {
    case german = "de"
    case english = "en"

    public var pack: LanguagePack {
        switch self {
        case .german: .german
        case .english: .english
        }
    }

    /// First-run choice: existing user files mean German; else the first preferred system language decides.
    public static func initial(preferredLanguages: [String], hasExistingFiles: Bool) -> DictationLanguage {
        if hasExistingFiles { return .german }
        guard let first = preferredLanguages.first else { return .english }
        return first.lowercased().hasPrefix("de") ? .german : .english
    }

    public var title: String {
        switch self {
        case .german: "Deutsch"
        case .english: "English"
        }
    }
}
