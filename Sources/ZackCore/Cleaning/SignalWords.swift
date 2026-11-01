/// Phrases that indicate a self-correction and trigger the language model.
public enum SignalWords {
    /// Minimum number of words before an ambiguous phrase.
    public static let minWordsBefore = 2

    public static func contains(_ text: String, language: DictationLanguage = .german) -> Bool {
        let pack = language.pack
        let words = TextTools.words(text)
        return occurs(pack.explicitSignals, in: words, from: 0)
            || occurs(pack.ambiguousSignals, in: words, from: minWordsBefore)
            || occurs(pack.negations, in: words, from: 1)
    }

    private static func occurs(_ candidates: [String], in words: [String], from start: Int) -> Bool {
        candidates.contains { phrase in
            let parts = phrase.split(separator: " ").map(String.init)
            guard words.count >= parts.count, start <= words.count - parts.count else { return false }
            return (start...(words.count - parts.count)).contains {
                words[$0..<($0 + parts.count)].elementsEqual(parts)
            }
        }
    }
}
