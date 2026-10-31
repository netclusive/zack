/// Phrases that indicate a self-correction and trigger the language model.
public enum SignalWords {
    /// Ambiguous phrases that also occur in ordinary speech; they count only after something to correct.
    public static let phrases = [
        "ich meine", "ich meinte", "moment", "sorry", "also nicht",
    ]

    /// "nein" and "nee" also correct a single word ("Morgen, nein, übermorgen"); at the start they answer.
    public static let negations = ["nein", "nee"]

    /// Explicit correction markers; they count anywhere.
    public static let explicitPhrases = [
        "korrektur", "streich das", "besser gesagt", "oder besser", "oder lieber", "vielmehr",
    ]

    /// Minimum number of words before an ambiguous phrase.
    public static let minWordsBefore = 2

    public static func contains(_ text: String) -> Bool {
        let words = TextTools.words(text)
        return occurs(explicitPhrases, in: words, from: 0) || occurs(phrases, in: words, from: minWordsBefore)
            || occurs(negations, in: words, from: 1)
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
