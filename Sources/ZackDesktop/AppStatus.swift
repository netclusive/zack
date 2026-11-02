/// Status line in the menu and the menu bar icon.
public enum AppStatus: Equatable, Sendable {
    case ready
    case recording
    /// Model on disk, still loading in the background.
    case loading
    case modelMissing
    case permissionMissing

    public enum Tone: Sendable {
        case green
        case blue
        case yellow
        case gray
    }

    /// `inputMonitoring` is nil when the hotkey does not need it.
    public static func evaluate(
        model: ModelStatus, modelLoaded: Bool, microphone: PermissionState, accessibility: Bool,
        inputMonitoring: Bool?, dictation: DictationState
    ) -> AppStatus {
        if dictation.isCapturing { return .recording }
        if model != .ready { return .modelMissing }
        if microphone != .granted || !accessibility || inputMonitoring == false { return .permissionMissing }
        return modelLoaded ? .ready : .loading
    }

    public func title(hotkey: HotkeyKey) -> String {
        switch self {
        case .ready: UIText.localized("Bereit · \(hotkey.title) halten")
        case .recording: UIText.localized("Nimmt auf")
        case .loading: UIText.localized("Modell wird geladen …")
        case .modelMissing: UIText.localized("Modell fehlt")
        case .permissionMissing: UIText.localized("Berechtigung fehlt")
        }
    }

    public var tone: Tone {
        switch self {
        case .ready: .green
        case .recording: .blue
        case .loading: .gray
        case .modelMissing, .permissionMissing: .yellow
        }
    }

    /// A click on the status line opens the setup window.
    public var opensSetup: Bool {
        self == .modelMissing || self == .permissionMissing
    }
}
