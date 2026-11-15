/// The term check: where the engine was unsure, a second recognizer hears the audio again with the vocabulary.
public enum TermCheck {
    /// Words below this confidence are marked; chosen on the bench corpora so that at most every 4th dictation is
    /// checked.
    public static let threshold: Float = 0.626
    /// Longer recordings are not checked.
    public static let maxAudioSeconds: Double = 30
    /// Longest wait for the second opinion; the dictation keeps the rule text after it.
    public static let timeout: Duration = .seconds(3)
}
