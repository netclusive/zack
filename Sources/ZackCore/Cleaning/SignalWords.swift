/// Phrases that indicate a self-correction and trigger the language model.
public enum SignalWords {
    /// Minimum number of words before an ambiguous phrase.
    public static let minWordsBefore = 2

    /// `text` is the rule output. `original` is the dictation before the rules ran; it decides the comma
    /// condition, with filler words of the language ignored, because the filler rule removes their commas.
    public static func contains(
        _ text: String, language: DictationLanguage = .german, original: String? = nil
    ) -> Bool {
        let pack = language.pack
        let tokens = TextTools.wordsWithCommas(text)
        let words = tokens.map(\.word)
        let commaBound = pack.commaBoundSignals
        let originalTokens = original.map { withoutFillers(TextTools.wordsWithCommas($0), pack.fillers) } ?? []
        let originalWords = originalTokens.map(\.word)
        func occurs(_ candidates: [String], from start: Int) -> Bool {
            candidates.contains { phrase in
                let parts = phrase.split(separator: " ").map(String.init)
                guard words.count >= parts.count, start <= words.count - parts.count else { return false }
                let needsComma = commaBound.contains(phrase)
                return (start...(words.count - parts.count)).contains {
                    words[$0..<($0 + parts.count)].elementsEqual(parts)
                        && (!needsComma || tokens[$0].afterComma
                            || commaBefore(parts, in: originalWords, flags: originalTokens))
                }
            }
        }
        return occurs(pack.explicitSignals, from: 0)
            || occurs(pack.ambiguousSignals, from: minWordsBefore)
            || occurs(pack.negations, from: 1)
    }

    /// Drops filler words; a comma before a dropped filler carries over to the next word.
    private static func withoutFillers(
        _ tokens: [(word: String, afterComma: Bool)], _ fillers: Set<String>
    ) -> [(word: String, afterComma: Bool)] {
        var result: [(word: String, afterComma: Bool)] = []
        var carried = false
        for token in tokens {
            if fillers.contains(token.word) {
                carried = carried || token.afterComma
            } else {
                result.append((token.word, token.afterComma || carried))
                carried = false
            }
        }
        return result
    }

    private static func commaBefore(
        _ parts: [String], in words: [String], flags: [(word: String, afterComma: Bool)]
    ) -> Bool {
        guard words.count >= parts.count else { return false }
        return (0...(words.count - parts.count)).contains {
            words[$0..<($0 + parts.count)].elementsEqual(parts) && flags[$0].afterComma
        }
    }
}
