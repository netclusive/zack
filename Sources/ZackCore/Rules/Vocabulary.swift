import Foundation

public struct Vocabulary: Sendable, Equatable {
    public struct Replacement: Sendable, Equatable {
        public let from: String
        public let to: String

        public init(from: String, to: String) {
            self.from = from
            self.to = to
        }
    }

    /// Canonical spellings; also passed to engines as hints.
    public var terms: [String]
    public var replacements: [Replacement]

    public init(terms: [String] = [], replacements: [Replacement] = []) {
        self.terms = terms
        self.replacements = replacements
    }
}

public enum VocabularyFile {
    /// One term per line, or `wrong => right`; the right side becomes a term as well.
    public static func parse(_ content: String) -> Vocabulary {
        var vocabulary = Vocabulary()
        for line in content.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            if let arrow = trimmed.range(of: "=>") {
                let from = trimmed[..<arrow.lowerBound].trimmingCharacters(in: .whitespaces)
                let to = trimmed[arrow.upperBound...].trimmingCharacters(in: .whitespaces)
                guard !from.isEmpty, !to.isEmpty else { continue }
                vocabulary.replacements.append(.init(from: from, to: to))
                if !vocabulary.terms.contains(to) { vocabulary.terms.append(to) }
            } else if !vocabulary.terms.contains(trimmed) {
                vocabulary.terms.append(trimmed)
            }
        }
        return vocabulary
    }
}

/// Applies replacements, then fixes the casing of known terms. Matches whole words only, case-insensitive.
public struct VocabularyRule: TextRule {
    private let rewrites: [(regex: NSRegularExpression, template: String)]

    public init(_ vocabulary: Vocabulary) {
        let replacements = vocabulary.replacements.map { ($0.from, $0.to) }
        let casing = vocabulary.terms.map { ($0, $0) }
        // Patterns are built from escaped words, so compilation cannot fail; skip defensively instead of crashing.
        rewrites = (replacements + casing).compactMap { from, to in
            guard let regex = try? NSRegularExpression(pattern: Self.pattern(for: from), options: [.caseInsensitive])
            else { return nil }
            return (regex, NSRegularExpression.escapedTemplate(for: to))
        }
    }

    public func apply(_ text: String, context: RuleContext) -> String {
        rewrites.reduce(text) { result, rewrite in
            rewrite.regex.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result), withTemplate: rewrite.template)
        }
    }

    private static func pattern(for phrase: String) -> String {
        let words = phrase.split(separator: " ").map { NSRegularExpression.escapedPattern(for: String($0)) }
        return #"(?<![\p{L}\p{N}])"# + words.joined(separator: #"[ \t]+"#) + #"(?![\p{L}\p{N}])"#
    }
}
