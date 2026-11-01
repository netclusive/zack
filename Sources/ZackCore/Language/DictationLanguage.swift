/// A language Zack can dictate in. One language per user; it selects the speech model and the language pack.
public enum DictationLanguage: String, CaseIterable, Sendable, Codable {
    case german = "de"
    case english = "en"

    public var pack: LanguagePack {
        switch self {
        case .german: .german
        case .english: .english
        }
    }

    public var title: String {
        switch self {
        case .german: "Deutsch"
        case .english: "English"
        }
    }
}
