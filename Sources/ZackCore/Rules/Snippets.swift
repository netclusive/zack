import Foundation

public struct Snippet: Sendable, Equatable, Codable {
    public let name: String
    public let text: String

    public init(name: String, text: String) {
        self.name = name
        self.text = text
    }
}

public enum SnippetFile {
    /// Parses lines `Name => Text`. `\n` in the text becomes a line break, `#` starts a comment line.
    public static func parse(_ content: String) -> [Snippet] {
        content.split(whereSeparator: \.isNewline).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let arrow = trimmed.range(of: "=>") else { return nil }
            let name = trimmed[..<arrow.lowerBound].trimmingCharacters(in: .whitespaces)
            let text = trimmed[arrow.upperBound...].trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "\\n", with: "\n")
            guard !name.isEmpty, !text.isEmpty else { return nil }
            return Snippet(name: name, text: text)
        }
    }
}

/// Replaces a dictation that consists only of "Baustein <Name>" with the stored text.
public struct SnippetRule: TextRule {
    private let texts: [String: String]

    public init(_ snippets: [Snippet]) {
        texts = Dictionary(
            snippets.map { (Self.normalizedName($0.name), $0.text) }, uniquingKeysWith: { first, _ in first })
    }

    public func match(_ text: String) -> String? {
        let words = TextTools.words(text)
        guard words.count >= 2, words[0] == "baustein" else { return nil }
        return texts[Self.normalizedName(words.dropFirst().joined(separator: " "))]
    }

    public func apply(_ text: String, context: RuleContext) -> String {
        match(text) ?? text
    }

    public static func normalizedName(_ name: String) -> String {
        // Speech engines often spell umlauts out, so fold them on both sides (words are already lowercased).
        let folds = [("ä", "ae"), ("ö", "oe"), ("ü", "ue"), ("ß", "ss")]
        return folds.reduce(TextTools.words(name).joined(separator: " ")) {
            $0.replacingOccurrences(of: $1.0, with: $1.1)
        }
    }
}
