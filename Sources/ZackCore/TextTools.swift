import Foundation

public enum TextTools {
    private static let innerWordCharacters = CharacterSet(charactersIn: "._-/")
    private static let wordCharacters = CharacterSet.alphanumerics.union(innerWordCharacters)

    /// Lowercased words without surrounding punctuation; dots, underscores, dashes and slashes inside words are kept.
    public static func words(_ text: String) -> [String] {
        wordsWithCommas(text).map(\.word)
    }

    /// The words of `words(_:)`, each flagged when a comma lies between it and the previous word, or the previous
    /// word ends with a period. A period inside a word ("readme.md") does not count.
    public static func wordsWithCommas(_ text: String) -> [(word: String, afterComma: Bool)] {
        var result: [(word: String, afterComma: Bool)] = []
        var token = String.UnicodeScalarView()
        var sawComma = false
        func flush() {
            let endsWithPeriod = token.last == "."
            let word = String(token).trimmingCharacters(in: innerWordCharacters)
            token = String.UnicodeScalarView()
            if !word.isEmpty {
                result.append((word, sawComma))
                sawComma = false
            }
            if endsWithPeriod { sawComma = true }
        }
        for scalar in text.lowercased().unicodeScalars {
            if wordCharacters.contains(scalar) {
                token.append(scalar)
            } else {
                flush()
                if scalar == "," { sawComma = true }
            }
        }
        flush()
        return result
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
