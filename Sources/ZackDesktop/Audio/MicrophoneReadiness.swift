/// "Mikrofon bereithalten": whether the input stays open between dictations.
public enum MicrophoneReadiness: String, CaseIterable, Sendable {
    /// Opens the input at key down and closes it after each dictation, as before.
    case off
    /// Keeps the input open for `window` after the last dictation.
    case afterDictation
    /// Keeps the input open from app start (once permission and model are there).
    case always

    /// Audio a warm input holds for the next dictation.
    public static let preRoll: Duration = .milliseconds(500)

    /// How long the input stays open after a dictation; nil for `off` (closes at once) and `always` (never).
    public var window: Duration? {
        self == .afterDictation ? .seconds(120) : nil
    }

    public var title: String {
        switch self {
        case .off: UIText.localized("Aus")
        case .afterDictation: UIText.localized("2 Minuten nach einem Diktat")
        case .always: UIText.localized("Immer")
        }
    }
}
