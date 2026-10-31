/// Menu bar image per status: the Zack Z while ready or loading, Lucide symbols otherwise.
public enum MenuBarSymbol: String, Sendable {
    case wave = "zack-wave"
    case recording = "lucide-mic"
    case alert = "lucide-circle-alert"

    public init(_ status: AppStatus) {
        switch status {
        case .ready, .loading: self = .wave
        case .recording: self = .recording
        case .modelMissing, .permissionMissing: self = .alert
        }
    }
}
