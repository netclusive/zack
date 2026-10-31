import Foundation

public enum TextTools {
    /// Filler words removed from dictations and ignored by metrics. "um" is a German preposition, so it is excluded.
    public static let fillers: Set<String> = ["äh", "ähm", "öh", "öhm", "hm", "hmm", "mhm", "uh"]

    private static let innerWordCharacters = CharacterSet(charactersIn: "._-/")
    private static let wordCharacters = CharacterSet.alphanumerics.union(innerWordCharacters)

    /// Lowercased words without surrounding punctuation; dots, underscores, dashes and slashes inside words are kept.
    public static func words(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: wordCharacters.inverted)
            .map { $0.trimmingCharacters(in: innerWordCharacters) }
            .filter { !$0.isEmpty }
    }

    /// Collapses spaces, removes spaces before punctuation and leading separators; keeps line breaks.
    public static func tidy(_ text: String) -> String {
        var result = text.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: #" ?\n ?"#, with: "\n", options: .regularExpression)
        result = result.replacingOccurrences(of: #" ([,.!?;:])"#, with: "$1", options: .regularExpression)
        result = result.trimmingCharacters(in: .whitespaces)
        result = result.replacingOccurrences(of: #"^[,;:] ?"#, with: "", options: .regularExpression)
        if result.allSatisfy({ $0.isPunctuation || $0.isWhitespace }) { return "" }
        return result
    }
}
