import Foundation

/// Code mode: spoken case commands, spoken file names, no trailing period for short commands.
public struct CodeModeRule: TextRule {
    enum Style: String, CaseIterable {
        case camel, snake, kebab, pascal

        func format(_ parts: [String]) -> String {
            switch self {
            case .camel: parts[0] + parts.dropFirst().map(\.capitalized).joined()
            case .pascal: parts.map(\.capitalized).joined()
            case .snake: parts.joined(separator: "_")
            case .kebab: parts.joined(separator: "-")
            }
        }
    }

    static let extensions = ["sh", "py", "js", "ts", "md", "json", "yml", "yaml", "swift", "php", "txt", "env", "toml"]
    static let maxIdentifierWords = 3
    /// A single word after the command is most likely prose, e.g. "snake case Problem".
    static let minIdentifierWords = 2

    public init() {}

    public func apply(_ text: String, context: RuleContext) -> String {
        guard context.mode == .code else { return text }
        return Self.dropShortTrailingPeriod(
            Self.joinFileNames(Self.applyCaseCommands(text, language: context.language), language: context.language))
    }

    static func applyCaseCommands(_ text: String, language: DictationLanguage = .german) -> String {
        let stopwords = language.pack.codeStopwords
        let tokens = text.split(separator: " ").map(String.init)
        var output: [String] = []
        var index = 0
        while index < tokens.count {
            guard let (style, commandLength) = caseCommand(at: index, in: tokens) else {
                output.append(tokens[index])
                index += 1
                continue
            }
            var cursor = index + commandLength
            var parts: [String] = []
            var trailing = ""
            while cursor < tokens.count, parts.count < maxIdentifierWords {
                let (word, punctuation) = splitTrailingPunctuation(tokens[cursor])
                if word.isEmpty || stopwords.contains(word.lowercased()) { break }
                parts.append(word.lowercased())
                cursor += 1
                if !punctuation.isEmpty {
                    trailing = punctuation
                    break
                }
            }
            if parts.count < minIdentifierWords {
                output.append(tokens[index])
                index += 1
            } else {
                output.append(style.format(parts) + trailing)
                index = cursor
            }
        }
        return output.joined(separator: " ")
    }

    static func caseCommand(at index: Int, in tokens: [String]) -> (Style, Int)? {
        let first = splitTrailingPunctuation(tokens[index]).0.lowercased()
        for style in Style.allCases {
            if first == style.rawValue + "case" { return (style, 1) }
            if first == style.rawValue, index + 1 < tokens.count,
                splitTrailingPunctuation(tokens[index + 1]).0.lowercased() == "case"
            {
                return (style, 2)
            }
        }
        return nil
    }

    static func splitTrailingPunctuation(_ token: String) -> (String, String) {
        var word = Substring(token)
        var punctuation = ""
        while let last = word.last, ",.!?;:".contains(last) {
            punctuation = String(last) + punctuation
            word = word.dropLast()
        }
        return (String(word), punctuation)
    }

    private static let germanFileNames = makeFileNamePattern(for: .german)
    private static let englishFileNames = makeFileNamePattern(for: .english)

    private static func makeFileNamePattern(for language: DictationLanguage) -> NSRegularExpression {
        let dotWord = NSRegularExpression.escapedPattern(for: language.pack.codeDotWord)
        // Built from the compiled-in language packs only: a broken pattern crashes the tests, never a user.
        return try! NSRegularExpression(
            pattern: #"(?<![\p{L}\p{N}])([\p{L}\p{N}_-]+)[ \t]+"# + dotWord + #"[ \t]+("#
                + extensions.joined(separator: "|") + #")(?![\p{L}\p{N}])"#,
            options: [.caseInsensitive])
    }

    private static func fileNamePattern(for language: DictationLanguage) -> NSRegularExpression {
        switch language {
        case .german: germanFileNames
        case .english: englishFileNames
        }
    }

    static func joinFileNames(_ text: String, language: DictationLanguage = .german) -> String {
        let regex = fileNamePattern(for: language)
        let mutable = NSMutableString(string: text)
        for match in regex.matches(in: text, range: NSRange(location: 0, length: mutable.length)).reversed() {
            let name = mutable.substring(with: match.range(at: 1))
            let ext = mutable.substring(with: match.range(at: 2)).lowercased()
            mutable.replaceCharacters(in: match.range, with: "\(name).\(ext)")
        }
        return mutable as String
    }

    static func dropShortTrailingPeriod(_ text: String) -> String {
        guard text.hasSuffix("."), !text.hasSuffix(".."), text.split(separator: " ").count < 4 else { return text }
        return String(text.dropLast())
    }
}
