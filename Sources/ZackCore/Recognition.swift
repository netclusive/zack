/// One recognized word as the engine wrote it, punctuation attached, with the engine's confidence (0 to 1).
public struct RecognizedWord: Sendable, Equatable {
    public let text: String
    public let confidence: Float

    public init(text: String, confidence: Float) {
        self.text = text
        self.confidence = confidence
    }
}

/// Recognized text and, if the engine reports them, its words with their confidence.
public struct Recognition: Sendable, Equatable {
    public let text: String
    /// Empty when the engine reports no confidences.
    public let words: [RecognizedWord]

    public init(text: String, words: [RecognizedWord] = []) {
        self.text = text
        self.words = words
    }
}
