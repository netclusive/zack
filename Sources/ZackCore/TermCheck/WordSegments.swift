import Foundation

/// A word or the text between two words, in its original spelling.
public struct WordSegment: Sendable, Equatable {
    public var text: String
    public var isWord: Bool
    /// Engine confidence of a word; nil for separators and for words that are never flagged.
    public var confidence: Float?

    public init(text: String, isWord: Bool, confidence: Float? = nil) {
        self.text = text
        self.isWord = isWord
        self.confidence = confidence
    }
}

public enum WordSegments {
    private static let innerCharacters = CharacterSet(charactersIn: "._-/")
    private static let wordCharacters = CharacterSet.alphanumerics.union(innerCharacters)

    /// Words as `TextTools.words` sees them, but with their case: runs of letters, digits and "._-/", without those
    /// four at the edges. Everything else is a separator. The segments join back to `text`.
    public static func split(_ text: String) -> [WordSegment] {
        var segments: [WordSegment] = []
        var separator = ""
        var run = ""
        func flushSeparator() {
            if !separator.isEmpty { segments.append(WordSegment(text: separator, isWord: false)) }
            separator = ""
        }
        func flushRun() {
            guard !run.isEmpty else { return }
            let scalars = Array(run.unicodeScalars)
            let start = scalars.firstIndex { !innerCharacters.contains($0) }
            guard let start, let end = scalars.lastIndex(where: { !innerCharacters.contains($0) }) else {
                separator += run
                run = ""
                return
            }
            separator += String(String.UnicodeScalarView(scalars[..<start]))
            flushSeparator()
            segments.append(WordSegment(text: String(String.UnicodeScalarView(scalars[start...end])), isWord: true))
            separator = String(String.UnicodeScalarView(scalars[(end + 1)...]))
            run = ""
        }
        for character in text {
            if character.unicodeScalars.allSatisfy(wordCharacters.contains) {
                run.append(character)
            } else {
                flushRun()
                separator.append(character)
            }
        }
        flushRun()
        flushSeparator()
        return segments
    }
}
