import ZackCore

/// Sanity check of a fresh recording, so silence or fragments are not saved by accident.
public enum RecordingReview {
    public enum Problem: Equatable, Sendable {
        case tooShort
        case silent

        public var message: String {
            switch self {
            case .tooShort: "Die Aufnahme ist zu kurz."
            case .silent: "Die Aufnahme ist still (Mikrofon stumm oder falsches Eingabegerät?)."
            }
        }
    }

    public static func problem(for clip: AudioClip) -> Problem? {
        if clip.duration < EngineLimits.minimumClipDuration { return .tooShort }
        if EngineLimits.isSilent(clip) { return .silent }
        return nil
    }
}
