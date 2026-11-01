import Foundation
import NaturalLanguage

/// Adapts spacing and the case of the first letter to the text left of the cursor.
/// Lowercases only words the tagger classifies as non-nouns, so German nouns keep their capital letter.
/// Packs with `lowercasesNouns` also lowercase common nouns, but not names, "I" or acronyms.
public struct CursorJoinRule: TextRule {
    private static let lowercasable: Set<NLTag> = [
        .verb, .adjective, .adverb, .pronoun, .determiner, .preposition, .conjunction, .particle, .interjection,
    ]

    private static let properNames: Set<NLTag> = [.personalName, .placeName, .organizationName]

    /// Vocabulary terms that keep their spelling when a dictation starts with them.
    private let keptTerms: Set<String>

    public init(keeping terms: [String] = []) {
        keptTerms = Set(terms)
    }

    public func apply(_ text: String, context: RuleContext) -> String {
        guard let before = context.textBeforeCursor, !text.isEmpty else { return text }
        // Text glued to a path or operator in code mode keeps its spelling and gets no space.
        if context.mode == .code, let last = before.last, Self.codeJoiners.contains(last) { return text }
        let lastVisible = before.last { !$0.isWhitespace }
        // "\r\n" is a single Character; any newline in the trailing whitespace starts a new line.
        let trailingWhitespace = before.reversed().prefix { $0.isWhitespace }
        let atLineStart = trailingWhitespace.contains { $0.isNewline }
        let atSentenceStart = lastVisible == nil || atLineStart || ".!?".contains(lastVisible ?? ".")

        var result = text
        if atSentenceStart {
            result = result.prefix(1).uppercased() + result.dropFirst()
        } else if Self.isLowercasable(firstWordOf: result, language: context.language, keeping: keptTerms) {
            result = result.prefix(1).lowercased() + result.dropFirst()
        }
        if let last = before.last, !last.isWhitespace, !Self.isOpening(last, in: before, language: context.language) {
            result = " " + result
        }
        return result
    }

    /// In code mode these characters glue the next word to the previous one (paths, options, assignments).
    private static let codeJoiners: Set<Character> = ["/", "\\", "-", "=", "~", "@"]

    /// Counts straight single quotes, ignoring apostrophes with a letter on both sides (e.g. "geht's").
    private static func quoteApostropheCount(in text: String) -> Int {
        let chars = Array(text)
        return chars.indices.filter { index in
            guard chars[index] == "'" else { return false }
            let inWord = index > 0 && index + 1 < chars.count && chars[index - 1].isLetter && chars[index + 1].isLetter
            return !inWord
        }.count
    }

    /// Whether `last` opens a bracket or quote, so no space follows. Straight quotes alternate: odd count means open.
    private static func isOpening(_ last: Character, in before: String, language: DictationLanguage) -> Bool {
        switch last {
        case "(", "[", "{": true
        case _ where language.pack.openingQuotes.contains(last): true
        case "\"": before.filter { $0 == last }.count % 2 == 1
        case "'": quoteApostropheCount(in: before) % 2 == 1
        default: false
        }
    }

    static func isLowercasable(firstWordOf text: String, language: DictationLanguage = .german, keeping terms: Set<String> = []
    ) -> Bool {
        let pack = language.pack
        guard let firstWord = text.split(separator: " ").first else { return false }
        let letters = firstWord.filter(\.isLetter)
        if letters.count > 1, letters.allSatisfy(\.isUppercase) { return false }  // acronyms such as API
        if pack.lowercasesNouns {
            // Compare the word without trailing punctuation and possessive ("I," or "Monday's").
            let core = firstWord.prefix { $0 != "'" && $0 != "\u{2019}" }.trimmingCharacters(in: .punctuationCharacters)
            if core == "I" || firstWord.hasPrefix("I'") || firstWord.hasPrefix("I\u{2019}") { return false }
            // Inner capitals (SharePoint, APIs), weekdays, months and vocabulary terms stay capitalised.
            if core.dropFirst().contains(where: \.isUppercase) { return false }
            if pack.alwaysCapitalized.contains(core.lowercased()) || terms.contains(core) { return false }
        }
        let tagger = NLTagger(tagSchemes: [.lexicalClass, .nameType])
        tagger.string = text
        tagger.setLanguage(pack.taggerLanguage, range: text.startIndex..<text.endIndex)
        guard let start = text.firstIndex(where: \.isLetter) else { return false }
        let (tag, _) = tagger.tag(at: start, unit: .word, scheme: .lexicalClass)
        guard let tag else { return false }
        guard pack.lowercasesNouns, tag == .noun else { return lowercasable.contains(tag) }
        // Proper names keep their capital letter.
        let (name, _) = tagger.tag(at: start, unit: .word, scheme: .nameType)
        return name.map { !properNames.contains($0) } ?? true
    }
}
