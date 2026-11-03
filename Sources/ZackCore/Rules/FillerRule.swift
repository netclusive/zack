import Foundation

/// Removes filler words including an adjacent comma and restores capitalization if a capitalized filler is removed.
public struct FillerRule: TextRule {
    private static let patterns: [DictationLanguage: NSRegularExpression] = Dictionary(
        uniqueKeysWithValues: DictationLanguage.allCases.map { ($0, makePattern(for: $0)) })

    private static func makePattern(for language: DictationLanguage) -> NSRegularExpression {
        let alternatives = language.pack.fillers.sorted { $0.count > $1.count }
            .map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        // Letters, digits and hyphens around a filler mean it is part of a longer word such as "uh-oh".
        let filler = #"(?<![\p{L}\p{N}-])(?:"# + alternatives + #")(?![\p{L}\p{N}-])"#
        let terminator = #"[.!?…]+"#
        // Consecutive fillers, optionally comma-separated.
        let run = filler + #"(?:,?[ \t]*"# + filler + #")*"#
        // A filler run that forms a whole line or sentence is removed together with its terminator.
        let sentence = #"(?<=[.!?…][ \t]{1,16})"# + run + terminator + #"[ \t]*"#
        // On a line of its own the line break goes too, so no empty line is left.
        let line = #"^"# + run + terminator + #"[ \t]*(?:\r?\n)?"#
        // "Er sagte: hm." -> "Er sagte."
        let afterColon = #"[:;][ \t]*"# + run + #"(?=[.!?…])"#
        let inline = #"(?:,[ \t]*)?"# + filler + #",?[ \t]*"#
        return try! NSRegularExpression(
            pattern: [line, sentence, afterColon, inline].joined(separator: "|"),
            options: [.caseInsensitive, .anchorsMatchLines])
    }

    public init() {}

    /// A match whose letters are all uppercase (e.g. "ER") is an acronym, not a filler.
    private static func isAcronym(_ matched: String) -> Bool {
        let letters = matched.filter(\.isLetter)
        return letters.count > 1 && letters.allSatisfy(\.isUppercase)
    }

    public func apply(_ text: String, context: RuleContext) -> String {
        let language = context.language
        let mutable = NSMutableString(string: text)
        let matches = Self.patterns[language]!.matches(
            in: text, range: NSRange(location: 0, length: mutable.length))
        for match in matches.reversed() {
            let matched = mutable.substring(with: match.range)
            if language.pack.keepsAcronymFillers, Self.isAcronym(matched) { continue }
            mutable.replaceCharacters(in: match.range, with: " ")
            let next = match.range.location + 1
            guard matched.first(where: \.isLetter)?.isUppercase == true, next < mutable.length else { continue }
            let range = mutable.rangeOfComposedCharacterSequence(at: next)
            mutable.replaceCharacters(in: range, with: mutable.substring(with: range).uppercased())
        }
        return TextTools.tidy(mutable as String)
    }
}
