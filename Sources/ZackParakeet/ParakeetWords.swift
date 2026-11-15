import FluidAudio
import Foundation
import ZackCore

/// Groups Parakeet's sub-word tokens into words, as FluidAudio's `buildWordTimings` does, keeping the confidence.
enum ParakeetWords {
    /// A word's confidence is the lowest of its tokens: one doubtful piece makes the word doubtful.
    static func group(_ timings: [TokenTiming]) -> [RecognizedWord] {
        var words: [RecognizedWord] = []
        var text = ""
        var confidence: Float = 1
        func flush() {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { words.append(RecognizedWord(text: trimmed, confidence: confidence)) }
            text = ""
            confidence = 1
        }
        for timing in timings {
            let token = timing.token
            if token.isEmpty || token == "<blank>" || token == "<pad>" { continue }
            if isWordBoundary(token) || text.isEmpty {
                flush()
                text = stripWordBoundaryPrefix(token)
            } else {
                text += token
            }
            confidence = min(confidence, timing.confidence)
        }
        flush()
        return words
    }
}
