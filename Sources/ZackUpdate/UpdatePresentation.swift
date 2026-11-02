/// State of the update entry in the menu.
public enum UpdateMenuState: Equatable, Sendable {
    case unavailable
    case idle
    case available(version: String)

    /// Disabled or highlighted menu line; nil when the regular check entry applies.
    public var title: String? {
        switch self {
        case .unavailable: UIText.localized("Updates nur in offiziellen Builds")
        case .idle: nil
        case .available(let version): UIText.localized("Update auf \(version) …")
        }
    }
}

public enum UpdatePresentation {
    /// Sparkle may show a scheduled update only in immediate focus (Zack launched recently or the system was idle for
    /// some time) and never during a dictation.
    public static func sparkleShowsScheduledUpdate(immediateFocus: Bool, dictating: Bool) -> Bool {
        immediateFocus && !dictating
    }
}
