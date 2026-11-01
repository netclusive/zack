/// Phrases that indicate a self-correction and trigger the language model.
public enum SignalWords {
    /// Minimum number of words before an ambiguous phrase.
    public static let minWordsBefore = 2

    public static func contains(_ text: String, language: DictationLanguage = .german) -> Bool {
        let pack = language.pack
        let tokens = TextTools.wordsWithCommas(text)
        let words = tokens.map(\.word)
        let commaBound = pack.commaBoundSignals
        func occurs(_ candidates: [String], from start: Int) -> Bool {
            candidates.contains { phrase in
                let parts = phrase.split(separator: " ").map(String.init)
                guard words.count >= parts.count, start <= words.count - parts.count else { return false }
                let needsComma = commaBound.contains(phrase)
                return (start...(words.count - parts.count)).contains {
                    words[$0..<($0 + parts.count)].elementsEqual(parts) && (!needsComma || tokens[$0].afterComma)
                }
            }
        }
        return occurs(pack.explicitSignals, from: 0)
            || occurs(pack.ambiguousSignals, from: minWordsBefore)
            || occurs(pack.negations, from: 1)
    }
}
